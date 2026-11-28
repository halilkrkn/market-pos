import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/sync_response.dart';
import 'tls_errors.dart';

abstract class SyncTransport {
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  });

  /// Mevcut ürüne stok girişi (delta) — `POST /api/v1/stock/receipts`.
  Future<SyncResponse> postStockReceipt({
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

  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
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

/// `OV-03`: Hub `restore_epoch` ve işlem makbuzlarını sorgulamak için opsiyonel
/// taşıma arayüzü (mevcut `SyncTransport` test sahtelerini kırmaz).
abstract interface class PostRestoreSyncTransport {
  Future<SyncResponse> getDeviceState({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SyncResponse> postSyncReceipts({
    required String hubUrl,
    required String token,
    required String deviceId,
    required List<int> clientSeqs,
    Duration timeout = const Duration(seconds: 10),
  });
}

/// MMS-001 & MMS-005: Kategori senkronizasyonu ve sayfalı ürün kataloğu çekimi
/// için opsiyonel taşıma arayüzü (mevcut `SyncTransport` test sahtelerini kırmaz).
abstract interface class CatalogExtendedSyncTransport {
  Future<SyncResponse> postCategoryUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SyncResponse> getProductsPage({
    required String hubUrl,
    required String token,
    required int limit,
    required int offset,
    Duration timeout = const Duration(seconds: 30),
  });
}

class HttpSyncTransport
    implements
        SyncTransport,
        PostRestoreSyncTransport,
        CatalogExtendedSyncTransport {
  final http.Client _client;

  /// Pilot tek-tenant/tek-store kimliği. Hub, mağaza verisi rotalarında
  /// `X-MMS-Tenant-Id` / `X-MMS-Store-Id` başlıklarını zorunlu tutar (ISO).
  final String? tenantId;
  final String? storeId;

  HttpSyncTransport([http.Client? client]) : this.forStore(client: client);

  /// Mağaza kimlik başlıklarını tüm Hub isteklerine ekleyen taşıyıcı.
  HttpSyncTransport.forStore({http.Client? client, this.tenantId, this.storeId})
      : _client = client ?? http.Client();

  /// S-3 uyumlu: Özel Kök CA Sertifikası güvenen HTTPS istemcisi üretir
  factory HttpSyncTransport.withCustomRootCa({
    required List<int> rootCaBytes,
    String? tenantId,
    String? storeId,
  }) {
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificatesBytes(rootCaBytes);
    final ioClient = HttpClient(context: context);
    return HttpSyncTransport.forStore(
      client: IOClient(ioClient),
      tenantId: tenantId,
      storeId: storeId,
    );
  }

  Map<String, String> _headers(String token) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        if (tenantId != null && tenantId!.isNotEmpty) 'x-mms-tenant-id': tenantId!,
        if (storeId != null && storeId!.isNotEmpty) 'x-mms-store-id': storeId!,
      };

  Future<SyncResponse> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      final resp = await request().timeout(timeout);
      return SyncResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
      );
    } on TlsPinMismatchException catch (e) {
      return SyncResponse.tlsPinMismatch(e);
    } on TlsCertificateValidationException catch (e) {
      return SyncResponse.tlsCertError(e);
    } on SocketException catch (e) {
      return SyncResponse.networkError('Ağ bağlantı hatası (SocketException): ${e.message}');
    } on HandshakeException catch (e) {
      return SyncResponse.networkError(
        'TLS el sıkışma / sertifika doğrulama hatası: ${e.message}',
        kind: SyncFailureKind.tlsHandshake,
      );
    } on TimeoutException catch (e) {
      return SyncResponse.networkError('Sunucu yanıt zaman aşımı (TimeoutException): ${e.message}');
    } on http.ClientException catch (e) {
      return SyncResponse.networkError('HTTP istemci hatası (ClientException): ${e.message}');
    } catch (e) {
      return SyncResponse.networkError('Beklenmeyen ağ hatası: $e');
    }
  }

  Future<SyncResponse> _postJson(
    String hubUrl,
    String path,
    String token,
    String body,
    Duration timeout,
  ) =>
      _send(
        () => _client.post(Uri.parse('$hubUrl$path'), headers: _headers(token), body: body),
        timeout,
      );

  Future<SyncResponse> _get(String hubUrl, String pathAndQuery, String token, Duration timeout) =>
      _send(() => _client.get(Uri.parse('$hubUrl$pathAndQuery'), headers: _headers(token)), timeout);

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(hubUrl, '/api/v1/sales', token, payload, timeout);

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(hubUrl, '/api/v1/products/upsert', token, payload, timeout);

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(hubUrl, '/api/v1/stock/receipts', token, payload, timeout);

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _get(hubUrl, '/api/v1/products', token, timeout);

  @override
  Future<SyncResponse> postCategoryUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(hubUrl, '/api/v1/categories/upsert', token, payload, timeout);

  @override
  Future<SyncResponse> getProductsPage({
    required String hubUrl,
    required String token,
    required int limit,
    required int offset,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _get(
        hubUrl,
        '/api/v1/products?limit=$limit&offset=$offset',
        token,
        timeout,
      );

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(
        hubUrl,
        '/api/v1/products/sync-ack',
        token,
        jsonEncode({'sync_session_id': syncSessionId}),
        timeout,
      );

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _get(hubUrl, '/api/v1/sales?cursor=$cursor&limit=$limit', token, timeout);

  @override
  Future<SyncResponse> getDeviceState({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _get(hubUrl, '/api/v1/sync/device-state', token, timeout);

  @override
  Future<SyncResponse> postSyncReceipts({
    required String hubUrl,
    required String token,
    required String deviceId,
    required List<int> clientSeqs,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _postJson(
        hubUrl,
        '/api/v1/sync/receipts',
        token,
        jsonEncode({'device_id': deviceId, 'client_seqs': clientSeqs}),
        timeout,
      );

  @override
  void close() {
    _client.close();
  }
}
