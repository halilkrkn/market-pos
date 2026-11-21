import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/network/api_exception.dart';
import 'package:mms_client_storage/mms_client_storage.dart'
    show
        TlsCertificateFailureKind,
        TlsCertificateValidationException,
        TlsPinMismatchException;

void main() {
  group('MmsApiClient - Sağlık Denetimi ve Ağ İletişimi Testleri', () {
    test('1. Başarılı Sağlık Kontrolü (200 OK): isHealthy=true ve SQLite sürümü alınır', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/health');
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

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceId: 'POS-WIN-01',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isTrue);
      expect(response.status, 'HEALTHY');
      expect(response.service, 'MARKET_MMS_HUB');
      expect(response.sqliteVersion, '3.45.1');
      expect(response.latencyMs, greaterThanOrEqualTo(0));
      expect(response.errorMessage, isNull);
    });

    test('1.1. Master Hub Gerçek Sağlık Yanıtı (UP): isHealthy=true doğrulanır', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response(
          jsonEncode({
            'status': 'UP',
            'timestamp': '2026-11-18T23:00:00.000Z',
            'sqlite_version': 'masked',
            'queue_metrics': {'total_enqueued': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://127.0.0.1:8945',
        deviceId: 'POS-WIN-01',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isTrue);
      expect(response.status, 'UP');
      expect(response.sqliteVersion, 'masked');
      expect(response.latencyMs, greaterThanOrEqualTo(0));
      expect(response.errorMessage, isNull);
    });

    test('1.2. Alternatif Başarılı Sağlık Durumu (OK): isHealthy=true doğrulanır', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://127.0.0.1:8945',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isTrue);
      expect(response.status, 'OK');
      expect(response.errorMessage, isNull);
    });

    test('1.3. Bilinmeyen / Bozuk Sağlık Durumu: isHealthy=false doğrulanır', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'DEGRADED',
            'service': 'MARKET_MMS_HUB',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://127.0.0.1:8945',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isFalse);
      expect(response.status, 'DEGRADED');
    });

    test('2. Sunucu Bakım / Draining Modunda (503 Service Unavailable): draining durumu dönülür', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'SERVICE_DRAINING'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isFalse);
      expect(response.status, 'DRAINING');
      expect(response.errorMessage, contains('503 Draining'));
    });

    test('3. Sunucu Kapalı / SocketException: Exception fırlatılmaz, güvenli OFFLINE modeli döner', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isFalse);
      expect(response.status, 'OFFLINE');
      expect(response.errorMessage, contains('Bağlantı kurulamadı'));
    });

    test('3b. Faz 7B: TLS pin uyuşmazlığı sıradan "bağlantı kurulamadı" hatası olarak gösterilmez', () async {
      final mockClient = MockClient((request) async {
        throw TlsPinMismatchException(
          host: '192.168.1.20',
          port: 8945,
          presentedSha256: 'EF' * 32,
        );
      });
      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://192.168.1.20:8945',
        deviceId: 'POS-AND-01',
      );

      final response = await apiClient.checkHealth();

      expect(response.isHealthy, isFalse);
      expect(response.status, 'TLS_PIN_MISMATCH');
      expect(response.errorMessage, contains('sertifika'));
      expect(response.errorMessage, isNot(contains('Bilinmeyen bağlantı hatası')));
    });

    test('4. Kimlik Doğrulama Başlıkları: DeviceToken ve X-Device-Id isteğe eklenir', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test_token_xyz_123');
        expect(request.headers['X-Device-Id'], 'POS-WIN-01');
        expect(request.headers['Content-Type'], 'application/json');

        return http.Response(jsonEncode({'success': true}), 200);
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceId: 'POS-WIN-01',
        deviceToken: 'test_token_xyz_123',
      );

      final result = await apiClient.post(
        '/api/v1/test',
        body: {'sample': 'data'},
      );
      expect(result['success'], isTrue);
    });

    test('5. Yetkisiz İstek (401 Unauthorized): AuthenticationException fırlatılır', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
      );

      expect(
        () => apiClient.get('/api/v1/products'),
        throwsA(isA<AuthenticationException>()),
      );
    });

    // =========================================================================
    // B-1 REMEDIATION TESTLERİ: HASSAS VERİ SIZINTISI ÖNLEME & SANİTİZASYON
    // =========================================================================

    test('6. B-1: 401 Hatasında Ham Sunucu Gövdesi ve Token Exception Mesajına Sızmaz', () async {
      const secretToken = 'secret_bearer_token_abc_999';
      final mockClient = MockClient((request) async {
        // Sunucu kasıtlı olarak hassas token ve dahili hata detayını döndürüyor
        return http.Response(
          jsonEncode({
            'status': 'error',
            'detail': 'Invalid token: $secretToken',
            'raw_auth': 'Bearer $secretToken',
            'stack': 'AuthMiddleware.verify() failed at /internal/auth.dart',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceToken: secretToken,
      );

      try {
        await apiClient.get('/api/v1/products');
        fail('AuthenticationException fırlatılmalıydı');
      } on AuthenticationException catch (e) {
        // 1. Ham gövdenin doğrudan mesaja sızmadığını doğrula
        expect(e.message, isNot(contains(secretToken)));
        expect(e.message, isNot(contains('AuthMiddleware')));
        expect(e.message, isNot(contains('raw_auth')));
        expect(e.toString(), isNot(contains(secretToken)));

        // 2. Güvenli sanitize edilmiş mesaj döndüğünü doğrula
        expect(e.message, contains('Yetkilendirme başarısız'));
        expect(e.statusCode, 401);
      }
    });

    test('7. B-1: 403 Hatasında Cihaz Yetkisi İptal Edildiğinde Hassas Veri Sızmaz', () async {
      const sensitiveSecret = 'super_confidential_db_secret_key';
      final mockClient = MockClient((request) async {
        return http.Response(
          'FORBIDDEN: token=$sensitiveSecret password=secret123',
          403,
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceToken: sensitiveSecret,
      );

      try {
        await apiClient.post('/api/v1/sales', body: {});
        fail('AuthenticationException fırlatılmalıydı');
      } on AuthenticationException catch (e) {
        expect(e.message, isNot(contains(sensitiveSecret)));
        expect(e.message, isNot(contains('password=secret123')));
        expect(e.toString(), isNot(contains(sensitiveSecret)));
        expect(e.message, contains('Erişim engellendi'));
        expect(e.statusCode, 403);
      }
    });

    test('8. B-1: Güvenli Hata Kodları (Whitelist) Ayıklanır ancak Serbest Metin Reddedilir', () async {
      // 8.1. Geçerli güvenli hata kodu (TOKEN_EXPIRED)
      final mockClientValid = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'TOKEN_EXPIRED'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClientValid = MmsApiClient(
        client: mockClientValid,
        baseUrl: 'https://127.0.0.1:8443',
      );

      try {
        await apiClientValid.get('/api/v1/products');
        fail('AuthenticationException fırlatılmalıydı');
      } on AuthenticationException catch (e) {
        expect(e.message, contains('[Kod: TOKEN_EXPIRED]'));
      }

      // 8.2. Güvensiz serbest metin (içinde SQL veya hassas mesaj barındıran güvensiz kod)
      final mockClientInvalid = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'SELECT * FROM users WHERE token=xyz_leak'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClientInvalid = MmsApiClient(
        client: mockClientInvalid,
        baseUrl: 'https://127.0.0.1:8443',
      );

      try {
        await apiClientInvalid.get('/api/v1/products');
        fail('AuthenticationException fırlatılmalıydı');
      } on AuthenticationException catch (e) {
        // Güvensiz metin whitelist kuralına uymadığı için mesaja dahil edilmemeli
        expect(e.message, isNot(contains('SELECT')));
        expect(e.message, isNot(contains('xyz_leak')));
        expect(e.message, isNot(contains('[Kod:')));
      }
    });

    test('9. B-1: ServerResponseException Hassas Yanıt Verilerini Maskeler ([REDACTED])', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INTERNAL_ERROR',
            'token': 'secret_auth_token_777',
            'password': 'my_db_password',
            'message': 'Failed with Bearer secret_bearer_999',
            'safe_info': 'General error info',
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
      );

      try {
        await apiClient.get('/api/v1/data');
        fail('ServerResponseException fırlatılmalıydı');
      } on ServerResponseException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, 'Sunucu hatası: HTTP 500');
        expect(e.responseData, isNotNull);
        expect(e.responseData!['token'], '[REDACTED]');
        expect(e.responseData!['password'], '[REDACTED]');
        expect(e.responseData!['message'], contains('Bearer [REDACTED]'));
        expect(e.responseData!['safe_info'], 'General error info');
      }
    });

    test('10. ADR-017: checkHealth SAN/IP sertifika hatasını TLS_CERT_ERROR olarak raporlar (TLS_PIN_MISMATCH değildir)', () async {
      final mockClient = MockClient((request) async {
        throw const TlsCertificateValidationException(
          kind: TlsCertificateFailureKind.ipAddressMismatch,
          host: '127.0.0.1',
          port: 8443,
          detail: 'IP address mismatch (secret_token_should_not_leak)',
        );
      });

      final apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
      );

      final health = await apiClient.checkHealth();
      expect(health.isHealthy, isFalse);
      expect(health.status, 'TLS_CERT_ERROR');
      expect(health.status, isNot('TLS_PIN_MISMATCH'));
      expect(health.errorMessage, isNotNull);
      expect(health.errorMessage, contains('SAN'));
      expect(health.errorMessage, isNot(contains('secret_token_should_not_leak')));
    });

    test('11. ADR-017 H-1: checkHealth ham HandshakeException durumunda OFFLINE yerine fail-closed TLS sınıflandırması döner', () async {
      final ipHandshakeApi = MmsApiClient(
        client: MockClient((_) async => throw const HandshakeException('CERTIFICATE_VERIFY_FAILED: IP address mismatch')),
        baseUrl: 'https://127.0.0.1:8443',
      );
      final ipHealth = await ipHandshakeApi.checkHealth();
      expect(ipHealth.status, 'TLS_CERT_ERROR');
      expect(ipHealth.status, isNot('OFFLINE'));

      final caHandshakeApi = MmsApiClient(
        client: MockClient((_) async => throw const HandshakeException('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate')),
        baseUrl: 'https://127.0.0.1:8443',
      );
      final caHealth = await caHandshakeApi.checkHealth();
      expect(caHealth.status, 'TLS_PIN_MISMATCH');
      expect(caHealth.status, isNot('OFFLINE'));
    });
  });
}
