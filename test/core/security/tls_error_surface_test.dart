import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/core/utils/user_friendly_error_mapper.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/diagnostics/presentation/widgets/status_badge.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _StaticCertErrorTransport implements SyncTransport {
  final SyncResponse response;

  _StaticCertErrorTransport(this.response);

  @override
  Future<SyncResponse> postSale({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  Future<SyncResponse> postProductUpsert({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  Future<SyncResponse> postStockReceipt({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  Future<SyncResponse> getProducts({required String hubUrl, required String token, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  Future<SyncResponse> getSales({required String hubUrl, required String token, int cursor = 0, int limit = 50, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  Future<SyncResponse> postSyncAck({required String hubUrl, required String token, required String syncSessionId, Duration timeout = const Duration(seconds: 10)}) async => response;

  @override
  void close() {}
}

void main() {
  group('ADR-017 H-2: TLS hata yüzeyleri (UserFriendlyErrorMapper, StatusBadge, SystemStatus, Coordinator)', () {
    test('1. UserFriendlyErrorMapper uzun Türkçe pin ve SAN/sertifika mesajlarını ve formatexception değerini doğru çevirir', () {
      final longPinError =
          'TLS_PIN_MISMATCH: Hub TLS sertifikası eşleştirmede sabitlenen parmak iziyle uyuşmuyor '
          '(192.168.1.50:8945). Sunulan SHA-256: ${'AB' * 32}. '
          'Bağlantı güvenlik nedeniyle reddedildi; Hub sertifikası yenilendiyse cihazı yeniden eşleştirin.';
      expect(longPinError.length, greaterThan(220));
      final mappedPin = UserFriendlyErrorMapper.map(longPinError);
      expect(mappedPin, contains('parmak izi'));
      expect(mappedPin, isNot(contains('Lütfen tekrar deneyin.')));

      const longCertError =
          'TLS_CERT_ERROR: Sertifika doğrulama hatası: Hub TLS sertifikası bağlantı IP adresini (SAN) '
          'doğrulamadı (192.168.1.50:8945). Sertifikanın IP SAN alanını veya Hub IP yapılandırmasını kontrol edin. '
          'Ek teknik bağlam metni uzunluğu 220 karakter sınırını aşmaktadır.';
      expect(longCertError.length, greaterThan(220));
      final mappedCert = UserFriendlyErrorMapper.map(longCertError);
      expect(mappedCert, contains('sertifika'));
      expect(mappedCert, isNot(contains('Lütfen tekrar deneyin.')));

      final mappedFmt = UserFriendlyErrorMapper.map(const FormatException('bozuk'));
      expect(mappedFmt, contains('beklenmeyen biçimde'));
    });

    testWidgets('2. StatusBadge tlsPinMismatch ve tlsCertError için ÇEVRİMDIŞI yerine özel rozet gösterir', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Column(
              children: [
                StatusBadge(state: BackendConnectionState.tlsPinMismatch),
                StatusBadge(state: BackendConnectionState.tlsCertError),
              ],
            ),
          ),
        ),
      );

      expect(find.text('SERTİFİKA UYUŞMUYOR'), findsOneWidget);
      expect(find.text('SERTİFİKA HATASI (SAN/TARİH)'), findsOneWidget);
      expect(find.textContaining('ÇEVRİMDIŞI'), findsNothing);
    });

    test('3. SystemStatusNotifier TLS_PIN_MISMATCH ve TLS_CERT_ERROR sağlık yanıtlarını ayrı BackendConnectionState olarak yansıtır', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final tempDir = await Directory.systemTemp.createTemp('mms_h2_status_');
      LocalDatabaseService.resetForTesting();
      late LocalDatabaseService localDb;
      addTearDown(() async {
        try {
          await localDb.database.close();
        } catch (_) {}
        LocalDatabaseService.resetForTesting();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      localDb = await LocalDatabaseService.initialize(customPath: p.join(tempDir.path, 'local.db'));

      var throwPin = true;
      final api = MmsApiClient(
        baseUrl: 'https://127.0.0.1:8945',
        client: MockClient((_) async {
          if (throwPin) {
            throw const TlsPinMismatchException(host: '127.0.0.1', port: 8945, presentedSha256: 'AA');
          }
          throw const TlsCertificateValidationException(
            kind: TlsCertificateFailureKind.ipAddressMismatch,
            host: '127.0.0.1',
            port: 8945,
          );
        }),
      );
      final notifier = SystemStatusNotifier(
        localDbService: localDb,
        apiClient: api,
        initialStatus: SystemStatus.initial(),
      );
      addTearDown(notifier.dispose);

      await notifier.refreshStatus();
      expect(notifier.state.backendState, BackendConnectionState.tlsPinMismatch);

      throwPin = false;
      await notifier.refreshStatus();
      expect(notifier.state.backendState, BackendConnectionState.tlsCertError);
    });

    test('4. BackgroundSyncCoordinator Outbox dolu veya boşken TLS_CERT_ERROR durumunu networkError yerine tlsCertError olarak bildirir', () async {
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);

      const certEx = TlsCertificateValidationException(
        kind: TlsCertificateFailureKind.ipAddressMismatch,
        host: '192.168.1.10',
        port: 8945,
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: repo,
        transport: _StaticCertErrorTransport(SyncResponse.tlsCertError(certEx)),
        deviceId: 'DEV1',
        readDeviceToken: () => 'tok',
        hubUrl: 'https://192.168.1.10:8945',
        autoStartTimer: false,
        enableLifecycleListener: false,
      );
      addTearDown(coordinator.dispose);

      // Boş Outbox iken bile downlink TLS cert hatası yakalanıp tlsCertError durumuna geçmeli
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.tlsCertError);

      // Outbox'ta bekleyen işlem varken de tlsCertError raporlanır
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('p1'),
          name: const Value('Ürün'),
          price: const Value(1000),
          stock: const Value(10000),
          updatedAt: Value(DateTime.now()),
        ),
      ]);
      await repo.createOfflineSale(
        deviceId: 'DEV1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('p1', 1)],
      );
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.tlsCertError);
      expect(coordinator.state.status, isNot(SyncCoordinatorStatus.networkError));
    });
  });
}
