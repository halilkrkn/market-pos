import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  group(
    'SystemStatusNotifier - Sistem Durumu ve Canlılık Yönetimi Testleri',
    () {
      late LocalDatabaseService localDb;

      setUp(() async {
        localDb = LocalDatabaseService.forTesting(NativeDatabase.memory());
      });

      tearDown(() async {
        await localDb.close();
      });

      test('1. Hub Çevrimiçi Olduğunda: BackendState online olur ve SQLite sürümü atanır', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'HEALTHY',
              'service': 'MARKET_MMS_HUB',
              'sqlite_version': '3.45.1',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = MmsApiClient(client: mockClient);
        final notifier = SystemStatusNotifier(
          apiClient: apiClient,
          localDbService: localDb,
          initialStatus: SystemStatus.initial(),
        );

        await notifier.refreshStatus();

        expect(notifier.state.backendState, BackendConnectionState.online);
        expect(notifier.state.backendSqliteVersion, '3.45.1');
        expect(notifier.state.localDbState, LocalDatabaseState.ready);
        expect(notifier.state.errorMessage, isNull);
        expect(notifier.state.outboxSummary.totalUnsynced, 0);
      });

      test('2. Hub Kapalı / Ulaşılamaz Olduğunda: BackendState offline olur ve hata mesajı saklanır', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Not Found', 404);
        });

        final apiClient = MmsApiClient(client: mockClient);
        final notifier = SystemStatusNotifier(
          apiClient: apiClient,
          localDbService: localDb,
          initialStatus: SystemStatus.initial(),
        );

        await notifier.refreshStatus();

        expect(notifier.state.backendState, BackendConnectionState.offline);
        expect(
          notifier.state.errorMessage,
          contains('Beklenmeyen HTTP Yanıtı: 404'),
        );
      });

      test('3. Outbox Kuyruk Durumu: refreshStatus ile OutboxSummary alanları doğru doldurulur', () async {
        final db = localDb.database;
        // 2 PENDING, 1 RETRY, 1 IN_PROGRESS, 1 FAILED_PERMANENT, 1 SYNCED ekle
        final entries = [
          ('op_1', 'PENDING'),
          ('op_2', 'PENDING'),
          ('op_3', 'RETRY'),
          ('op_4', 'IN_PROGRESS'),
          ('op_5', 'FAILED_PERMANENT'),
          ('op_6', 'SYNCED'),
        ];

        for (var i = 0; i < entries.length; i++) {
          await db.into(db.outboxOperations).insert(
                OutboxOperationsCompanion.insert(
                  operationId: entries[i].$1,
                  deviceId: 'POS-WIN-01',
                  clientSeq: i + 1,
                  operationType: 'SALE_CREATE',
                  payload: '{"test": true}',
                  payloadHash: 'hash_$i',
                  occurredAt: DateTime.now(),
                  status: Value(entries[i].$2),
                ),
              );
        }

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'status': 'HEALTHY'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = MmsApiClient(client: mockClient);
        final notifier = SystemStatusNotifier(
          apiClient: apiClient,
          localDbService: localDb,
          initialStatus: SystemStatus.initial(),
        );

        await notifier.refreshStatus();

        final summary = notifier.state.outboxSummary;
        expect(summary.pending, 2);
        expect(summary.retry, 1);
        expect(summary.inProgress, 1);
        expect(summary.failedPermanent, 1);
        expect(summary.totalUnsynced, 5); // SYNCED hariç
        expect(summary.hasErrors, isTrue);
        expect(summary.hasPendingWork, isTrue);

        // Geriye dönük uyumluluk: pendingOutboxCount yalnızca PENDING saymalı (2)
        expect(notifier.state.pendingOutboxCount, 2);
      });

      test('4. outboxSummaryProvider: Reaktif güncelleme, kayıt ekleme ve deterministik refreshStatus doğrulaması', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'status': 'HEALTHY'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = MmsApiClient(client: mockClient);

        final container = ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            apiClientProvider.overrideWithValue(apiClient),
          ],
        );
        addTearDown(container.dispose);

        // 1. Önce boş Outbox durumunu doğrula
        final initialSummary = container.read(outboxSummaryProvider);
        expect(initialSummary.totalUnsynced, 0);
        expect(initialSummary.hasPendingWork, isFalse);
        expect(initialSummary.hasErrors, isFalse);

        // 2. Outbox'a yeni kayıt ekle (1 PENDING, 1 RETRY)
        final db = localDb.database;
        await db.into(db.outboxOperations).insert(
              OutboxOperationsCompanion.insert(
                operationId: 'reaktif_op_1',
                deviceId: 'POS-WIN-01',
                clientSeq: 101,
                operationType: 'SALE_CREATE',
                payload: '{"test": 1}',
                payloadHash: 'hash_reaktif_1',
                occurredAt: DateTime.now(),
                status: const Value('PENDING'),
              ),
            );
        await db.into(db.outboxOperations).insert(
              OutboxOperationsCompanion.insert(
                operationId: 'reaktif_op_2',
                deviceId: 'POS-WIN-01',
                clientSeq: 102,
                operationType: 'SALE_CREATE',
                payload: '{"test": 2}',
                payloadHash: 'hash_reaktif_2',
                occurredAt: DateTime.now(),
                status: const Value('RETRY'),
              ),
            );

        // 3. refreshStatus() çağır (deterministik async - sabit bekleme süresi yok)
        await container.read(systemStatusProvider.notifier).refreshStatus();

        // 4. outboxSummaryProvider üzerinden güncel sayının yayınlandığını doğrula
        final updatedSummary = container.read(outboxSummaryProvider);
        expect(updatedSummary.totalUnsynced, 2);
        expect(updatedSummary.pending, 1);
        expect(updatedSummary.retry, 1);
        expect(updatedSummary.hasPendingWork, isTrue);
        expect(updatedSummary.hasErrors, isFalse);
      });

      test('5. Veritabanı Hatasında: DB hatası oluştuğunda localDbState error olur ve hata mesajı atanır', () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'status': 'HEALTHY'}), 200,
              headers: {'content-type': 'application/json'});
        });

        // Veritabanını kapatıp hata tetikle
        await localDb.close();

        final apiClient = MmsApiClient(client: mockClient);
        final notifier = SystemStatusNotifier(
          apiClient: apiClient,
          localDbService: localDb,
          initialStatus: SystemStatus.initial(),
        );

        await notifier.refreshStatus();

        expect(notifier.state.localDbState, LocalDatabaseState.error);
        expect(notifier.state.errorMessage, contains('Yerel veritabanı okuma hatası'));
      });
    },
  );
}
