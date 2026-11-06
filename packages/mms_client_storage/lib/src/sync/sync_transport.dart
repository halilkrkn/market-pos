import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/sync_response.dart';

abstract class SyncTransport {
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  });

  void close();
}

class HttpSyncTransport implements SyncTransport {
  final http.Client _client;

  HttpSyncTransport([http.Client? client]) : _client = client ?? http.Client();

  /// S-3 uyumlu: Özel Kök CA Sertifikası güvenen HTTPS istemcisi üretir
  factory HttpSyncTransport.withCustomRootCa({
    required List<int> rootCaBytes,
  }) {
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificatesBytes(rootCaBytes);
    final ioClient = HttpClient(context: context);
    return HttpSyncTransport(IOClient(ioClient));
  }

  /// Güvensiz geliştirme/test ortamı için (Self-signed sertifikaları kabul eden istemci)
  factory HttpSyncTransport.insecureForTesting() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return HttpSyncTransport(IOClient(ioClient));
  }

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$hubUrl/api/v1/sales');
    try {
      final resp = await _client
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: payload,
          )
          .timeout(timeout);

      return SyncResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
      );
    } on SocketException catch (e) {
      return SyncResponse.networkError('Ağ bağlantı hatası (SocketException): ${e.message}');
    } on TimeoutException catch (e) {
      return SyncResponse.networkError('Sunucu yanıt zaman aşımı (TimeoutException): ${e.message}');
    } on http.ClientException catch (e) {
      return SyncResponse.networkError('HTTP istemci hatası (ClientException): ${e.message}');
    } catch (e) {
      return SyncResponse.networkError('Beklenmeyen ağ hatası: $e');
    }
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$hubUrl/api/v1/products');
    try {
      final resp = await _client.get(
        uri,
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      return SyncResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
      );
    } on SocketException catch (e) {
      return SyncResponse.networkError('Ağ bağlantı hatası: ${e.message}');
    } on TimeoutException catch (e) {
      return SyncResponse.networkError('Zaman aşımı: ${e.message}');
    } catch (e) {
      return SyncResponse.networkError('Beklenmeyen hata: $e');
    }
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$hubUrl/api/v1/products/sync-ack');
    try {
      final resp = await _client
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({'sync_session_id': syncSessionId}),
          )
          .timeout(timeout);

      return SyncResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
      );
    } on SocketException catch (e) {
      return SyncResponse.networkError('Ağ bağlantı hatası (SocketException): ${e.message}');
    } on TimeoutException catch (e) {
      return SyncResponse.networkError('Sunucu yanıt zaman aşımı (TimeoutException): ${e.message}');
    } on http.ClientException catch (e) {
      return SyncResponse.networkError('HTTP istemci hatası (ClientException): ${e.message}');
    } catch (e) {
      return SyncResponse.networkError('Beklenmeyen ağ hatası: $e');
    }
  }

  @override
  void close() {
    _client.close();
  }
}
