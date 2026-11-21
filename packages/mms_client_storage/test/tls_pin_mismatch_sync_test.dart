import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:test/test.dart';

/// Faz 7B — TLS pin uyuşmazlığı sıradan ağ hatası gibi gösterilmez (TDD).
class _PinMismatchTransport implements SyncTransport {
  int calls = 0;

  SyncResponse _mismatch() {
    calls++;
    return SyncResponse.tlsPinMismatch(
      TlsPinMismatchException(
        host: '192.168.1.10',
        port: 8945,
        presentedSha256: 'AB' * 32,
      ),
    );
  }

  @override
  Future<SyncResponse> postSale({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  Future<SyncResponse> postProductUpsert({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  Future<SyncResponse> postStockReceipt({required String hubUrl, required String token, required String payload, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  Future<SyncResponse> getProducts({required String hubUrl, required String token, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  Future<SyncResponse> getSales({required String hubUrl, required String token, int cursor = 0, int limit = 50, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  Future<SyncResponse> postSyncAck({required String hubUrl, required String token, required String syncSessionId, Duration timeout = const Duration(seconds: 10)}) async => _mismatch();

  @override
  void close() {}
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Faz 7B: TLS pin uyuşmazlığı sınıflandırması', () {
    test('1. HttpSyncTransport pin uyuşmazlığını ayrı tür olarak raporlar (ağ hatası metnine gömülmez)', () async {
      final transport = HttpSyncTransport(MockClient((_) async {
        throw TlsPinMismatchException(
          host: '192.168.1.10',
          port: 8945,
          presentedSha256: 'CD' * 32,
        );
      }));

      final resp = await transport.postSale(hubUrl: 'https://192.168.1.10:8945', token: 't', payload: '{}');

      expect(resp.isTlsPinMismatch, isTrue);
      expect(resp.failureKind, SyncFailureKind.tlsPinMismatch);
      expect(resp.errorMessage, contains('CD' * 32), reason: 'Sunulan parmak izi tanılama için raporlanmalı');
    });

    test('2. Sıradan ağ hatası pin uyuşmazlığı olarak işaretlenmez', () async {
      final transport = HttpSyncTransport(MockClient((_) async => throw http.ClientException('Connection refused')));
      final resp = await transport.postSale(hubUrl: 'https://192.168.1.10:8945', token: 't', payload: '{}');
      expect(resp.isNetworkError, isTrue);
      expect(resp.isTlsPinMismatch, isFalse);
      expect(resp.failureKind, SyncFailureKind.network);
    });

    test('3. ClientSyncService: pin uyuşmazlığında kayıt korunur (RETRY), hızlı yeniden deneme yapılmaz ve sonuç işaretlenir', () async {
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('p1'),
          name: const Value('Ürün'),
          price: const Value(1000),
          stock: const Value(10000),
          updatedAt: Value(DateTime.now()),
        ),
      ]);
      await repo.createOfflineSale(deviceId: 'DEV1', paymentMethod: 'CASH', items: [CartItemInput.units('p1', 1)]);

      final transport = _PinMismatchTransport();
      final now = DateTime.utc(2026, 11, 21, 10);
      final service = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'DEV1',
        deviceToken: 'token',
        hubUrl: 'https://192.168.1.10:8945',
        maxBackoff: const Duration(minutes: 5),
      );

      final result = await service.syncPendingOutbox(now: now);

      expect(result.tlsPinMismatch, isTrue);
      expect(result.permanentFailedCount, 0);
      final op = await db.select(db.outboxOperations).getSingle();
      expect(op.status, 'RETRY', reason: 'Güvenlik hatası veri hatası değildir; kayıt silinmez/kilitlenmez');
      expect(op.lastError, startsWith('TLS_PIN_MISMATCH'));
      expect(op.nextRetryAt!.toUtc(), now.add(const Duration(minutes: 5)),
          reason: 'Uyuşmayan sunucuya token gönderilmemesi için en uzun bekleme uygulanmalı');
      expect(jsonDecode(op.payload)['client_seq'], 1);
    });

    test('4. ADR-017: SAN/IP sertifika doğrulama hatasında tlsCertError ayrı sınıflanır, Outbox RETRY korunur ve HTTP fallback yapılmaz', () async {
      final requestedSchemes = <String>[];
      final transport = HttpSyncTransport(MockClient((req) async {
        requestedSchemes.add(req.url.scheme);
        throw const TlsCertificateValidationException(
          kind: TlsCertificateFailureKind.ipAddressMismatch,
          host: '192.168.1.10',
          port: 8945,
          detail: 'IP address mismatch',
        );
      }));

      final resp = await transport.postSale(
        hubUrl: 'https://192.168.1.10:8945',
        token: 'tok',
        payload: '{}',
      );
      expect(resp.isSuccess, isFalse);
      expect(resp.isTlsPinMismatch, isFalse);
      expect(resp.isTlsCertError, isTrue);
      expect(resp.failureKind, SyncFailureKind.tlsCertError);
      expect(requestedSchemes, ['https']);

      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('p1'),
          name: const Value('Ürün'),
          price: const Value(1000),
          stock: const Value(10000),
          updatedAt: Value(DateTime.now()),
        ),
      ]);
      await repo.createOfflineSale(deviceId: 'DEV1', paymentMethod: 'CASH', items: [CartItemInput.units('p1', 1)]);

      final schemes = <String>[];
      final retryingTransport = HttpSyncTransport(MockClient((req) async {
        schemes.add(req.url.scheme);
        throw const TlsCertificateValidationException(
          kind: TlsCertificateFailureKind.ipAddressMismatch,
          host: '192.168.1.10',
          port: 8945,
          detail: 'IP address mismatch',
        );
      }));

      final now = DateTime.utc(2026, 11, 21, 10);
      final service = ClientSyncService(
        repository: repo,
        transport: retryingTransport,
        deviceId: 'DEV1',
        deviceToken: 'token',
        hubUrl: 'https://192.168.1.10:8945',
        maxBackoff: const Duration(minutes: 5),
      );

      final result = await service.syncPendingOutbox(now: now);
      expect(result.tlsPinMismatch, isFalse);
      expect(result.tlsCertError, isTrue);
      expect(result.permanentFailedCount, 0);
      expect(schemes, isNotEmpty);
      expect(schemes.every((s) => s == 'https'), isTrue, reason: 'HTTP fallback kesinlikle yapılmamalı');
      final op = await db.select(db.outboxOperations).getSingle();
      expect(op.status, 'RETRY');
      expect(op.lastError, startsWith('TLS_CERT_ERROR'));
      expect(op.nextRetryAt!.toUtc(), now.add(const Duration(minutes: 5)));
      expect(jsonDecode(op.payload)['client_seq'], 1);
    });

    test('5. ADR-017 H-2: Outbox boşken syncSales ve syncProducts TLS hatalarını yutmaz', () async {
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);
      await repo.initializeDevice('DEV1');

      final certTransport = HttpSyncTransport(MockClient((_) async {
        throw const TlsCertificateValidationException(
          kind: TlsCertificateFailureKind.ipAddressMismatch,
          host: '192.168.1.10',
          port: 8945,
        );
      }));

      final service = ClientSyncService(
        repository: repo,
        transport: certTransport,
        deviceId: 'DEV1',
        deviceToken: 'token',
        hubUrl: 'https://192.168.1.10:8945',
      );

      await expectLater(
        () => service.syncProducts(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('TLS_CERT_ERROR'))),
      );
      await expectLater(
        () => service.syncSales(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('TLS_CERT_ERROR'))),
      );
    });
  });
}
