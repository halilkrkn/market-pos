// S6: E2E testinin üretim Hub'ına yazmasını engelleyen hedef doğrulayıcının birim testleri.
// Ağ erişimi yoktur; Hub yanıtları sahte taşıyıcı ile taklit edilir.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../integration_test/support/e2e_hub_target_guard.dart';

class _FakeIdentityTransport implements PostRestoreSyncTransport {
  final SyncResponse response;
  int deviceStateCalls = 0;
  int writeCalls = 0;

  _FakeIdentityTransport(this.response);

  @override
  Future<SyncResponse> getDeviceState({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    deviceStateCalls++;
    return response;
  }

  @override
  Future<SyncResponse> postSyncReceipts({
    required String hubUrl,
    required String token,
    required String deviceId,
    required List<int> clientSeqs,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    writeCalls++;
    throw StateError('Kimlik doğrulayıcı yazma yapmamalı');
  }
}

void main() {
  group('S6 E2eHubTargetGuard.validateTarget (çevrimdışı, fail-closed)', () {
    const url = 'https://192.168.50.10:9443';
    const allow = '192.168.50.10:9443';

    test('Allowlist + test Hub kimliği tanımlı ve eşleşiyorsa kabul edilir', () {
      expect(
        () => E2eHubTargetGuard.validateTarget(
          hubUrl: url,
          allowlistCsv: ' 10.0.0.5:8945 , $allow ',
          expectedHubId: 'E2E-HUB-01',
        ),
        returnsNormally,
      );
    });

    test('Varsayılan: allowlist veya beklenen kimlik yoksa reddedilir', () {
      expect(
        () => E2eHubTargetGuard.validateTarget(hubUrl: url, allowlistCsv: '', expectedHubId: 'E2E-HUB-01'),
        throwsA(isA<E2eHubTargetRejected>()),
      );
      expect(
        () => E2eHubTargetGuard.validateTarget(hubUrl: url, allowlistCsv: allow, expectedHubId: ''),
        throwsA(isA<E2eHubTargetRejected>()),
      );
    });

    test('Üretim/varsayılan Hub kimlikleri (MMS-HUB-MASTER, HUB-PILOT-01) reddedilir', () {
      for (final prodId in ['MMS-HUB-MASTER', 'HUB-PILOT-01', 'e2e', 'E2E-', 'TESTHUB']) {
        expect(
          () => E2eHubTargetGuard.validateTarget(hubUrl: url, allowlistCsv: allow, expectedHubId: prodId),
          throwsA(isA<E2eHubTargetRejected>()),
          reason: prodId,
        );
      }
    });

    test('Allowlist dışındaki adres (farklı host veya port, örtük port) reddedilir', () {
      for (final other in [
        'https://192.168.50.11:9443',
        'https://192.168.50.10:8945',
        'https://192.168.50.10',
      ]) {
        expect(
          () => E2eHubTargetGuard.validateTarget(hubUrl: other, allowlistCsv: allow, expectedHubId: 'TEST-HUB-A'),
          throwsA(isA<E2eHubTargetRejected>()),
          reason: other,
        );
      }
    });

    test('Bozuk allowlist girdisi ve geçersiz şema reddedilir', () {
      expect(
        () => E2eHubTargetGuard.validateTarget(hubUrl: url, allowlistCsv: '192.168.50.10', expectedHubId: 'E2E-HUB-01'),
        throwsA(isA<E2eHubTargetRejected>()),
      );
      expect(
        () => E2eHubTargetGuard.validateTarget(
          hubUrl: 'ftp://192.168.50.10:9443',
          allowlistCsv: allow,
          expectedHubId: 'E2E-HUB-01',
        ),
        throwsA(isA<E2eHubTargetRejected>()),
      );
    });
  });

  group('S6 E2eHubTargetGuard.verifyHubIdentity (salt-okunur)', () {
    test('Hub kimliği beklenen test kimliğiyle eşleşirse geçer; yazma yapılmaz', () async {
      final t = _FakeIdentityTransport(SyncResponse(
        statusCode: 200,
        body: jsonEncode({'hub_id': 'E2E-HUB-01', 'tenant_id': 't', 'store_id': 's'}),
      ));
      await E2eHubTargetGuard.verifyHubIdentity(
        transport: t,
        hubUrl: 'https://192.168.50.10:9443',
        deviceToken: 'tok',
        expectedHubId: 'E2E-HUB-01',
      );
      expect(t.deviceStateCalls, 1);
      expect(t.writeCalls, 0);
    });

    test('Aynı adreste üretim Hub çalışıyorsa (kimlik farklı) reddedilir', () async {
      final t = _FakeIdentityTransport(SyncResponse(
        statusCode: 200,
        body: jsonEncode({'hub_id': 'MMS-HUB-MASTER'}),
      ));
      await expectLater(
        E2eHubTargetGuard.verifyHubIdentity(
          transport: t,
          hubUrl: 'https://192.168.50.10:9443',
          deviceToken: 'tok',
          expectedHubId: 'E2E-HUB-01',
        ),
        throwsA(isA<E2eHubTargetRejected>()),
      );
      expect(t.writeCalls, 0);
    });

    test('Kimlik okunamazsa (401 / ağ hatası / bozuk yanıt) reddedilir', () async {
      for (final r in [
        const SyncResponse(statusCode: 401, body: '{}'),
        const SyncResponse(statusCode: 0, body: '', isNetworkError: true),
        const SyncResponse(statusCode: 200, body: 'not-json'),
      ]) {
        await expectLater(
          E2eHubTargetGuard.verifyHubIdentity(
            transport: _FakeIdentityTransport(r),
            hubUrl: 'https://192.168.50.10:9443',
            deviceToken: 'tok',
            expectedHubId: 'E2E-HUB-01',
          ),
          throwsA(isA<E2eHubTargetRejected>()),
        );
      }
    });
  });
}
