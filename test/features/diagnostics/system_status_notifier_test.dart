import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';

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
    },
  );
}
