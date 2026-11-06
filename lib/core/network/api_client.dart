import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../constants/app_constants.dart';
import 'api_exception.dart';
import 'api_response.dart';

/// MARKET MMS - Merkezi Shelf Backend İle İletişim Kurucu API İstemcisi
class MmsApiClient {
  final http.Client _client;
  final String baseUrl;
  final String? deviceToken;
  final String deviceId;
  final Duration timeout;

  MmsApiClient({
    http.Client? client,
    this.baseUrl = AppConstants.defaultBackendBaseUrl,
    this.deviceToken,
    this.deviceId = AppConstants.defaultDeviceId,
    this.timeout = AppConstants.defaultTimeout,
  }) : _client = client ?? http.Client();

  /// Standart İstek Başlıkları
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Device-Id': deviceId,
    };
    if (deviceToken != null && deviceToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $deviceToken';
    }
    return headers;
  }

  /// Merkezi Hub Sağlık Denetimi (GET /health)
  ///
  /// Gecikme süresini (latency) ms cinsinden hesaplar.
  /// Sunucu kapalı veya ulaşılamaz ise güvenli bir biçimde 'OFFLINE' modeli döner (Exception fırlatmaz).
  Future<CentralHealthResponse> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl${ApiEndpoints.health}');

    try {
      final response = await _client.get(uri).timeout(timeout);
      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CentralHealthResponse.fromJson(data, latencyMs: latencyMs);
      } else if (response.statusCode == 503) {
        return CentralHealthResponse.draining(
          errorMessage: 'Merkezi servis bakım/restore modunda (503 Draining).',
          latencyMs: latencyMs,
        );
      } else {
        return CentralHealthResponse.unreachable(
          errorMessage: 'Beklenmeyen HTTP Yanıtı: ${response.statusCode}',
          latencyMs: latencyMs,
        );
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      return CentralHealthResponse.unreachable(
        errorMessage: _sanitizeString('Bağlantı kurulamadı: ${e.message}'),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return CentralHealthResponse.unreachable(
        errorMessage: 'İstek zaman aşımına uğradı (${timeout.inSeconds} sn).',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on http.ClientException catch (e) {
      stopwatch.stop();
      return CentralHealthResponse.unreachable(
        errorMessage: _sanitizeString('İstemci hatası: ${e.message}'),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return CentralHealthResponse.unreachable(
        errorMessage: _sanitizeString('Bilinmeyen bağlantı hatası: $e'),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// GET İsteği Yürütücü
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint')
        .replace(queryParameters: queryParameters);

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      return _processResponse(response);
    } on SocketException catch (e) {
      throw NetworkException(
        _sanitizeString('Ağ bağlantısı yok veya sunucuya erişilemiyor: ${e.message}'),
      );
    } on TimeoutException {
      throw NetworkException(
        'Sunucu yanıt vermedi (Zaman aşımı: ${timeout.inSeconds} sn).',
      );
    }
  }

  /// POST İsteği Yürütücü
  Future<Map<String, dynamic>> post(
    String endpoint, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      return _processResponse(response);
    } on SocketException catch (e) {
      throw NetworkException(
        _sanitizeString('Ağ bağlantısı yok veya sunucuya erişilemiyor: ${e.message}'),
      );
    } on TimeoutException {
      throw NetworkException(
        'Sunucu yanıt vermedi (Zaman aşımı: ${timeout.inSeconds} sn).',
      );
    }
  }

  /// Ortak Yanıt Çözümleyici ve Hata Yöneticisi
  Map<String, dynamic> _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return {'raw': response.body};
      }
    }

    if (response.statusCode == 503) {
      throw const ServiceDrainingException(
        'Sunucu şu anda işlem kabul etmiyor (503 Service Draining).',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthenticationException(
        _sanitizeAuthErrorMessage(response),
        statusCode: response.statusCode,
      );
    }

    Map<String, dynamic>? errorData;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        errorData = _sanitizeResponseData(decoded);
      }
    } catch (_) {}

    throw ServerResponseException(
      'Sunucu hatası: HTTP ${response.statusCode}',
      statusCode: response.statusCode,
      responseData: errorData,
    );
  }

  /// B-1: Yetkilendirme Hata Mesajı Sanitizasyonu
  ///
  /// Sunucudan gelen ham response.body ASLA doğrudan mesaja eklenmez.
  /// Yalnızca güvenli, doğrulanmış hata kodları ayıklanır; token ve hassas veriler maskelenir.
  String _sanitizeAuthErrorMessage(http.Response response) {
    final safeCode = _extractSafeErrorCode(response.body);
    final codeSuffix = safeCode != null ? ' [Kod: $safeCode]' : '';

    final String baseMessage;
    if (response.statusCode == 401) {
      baseMessage = 'Yetkilendirme başarısız: Cihaz kimliği veya token geçersiz (HTTP 401)';
    } else if (response.statusCode == 403) {
      baseMessage = 'Erişim engellendi: Cihaz yetkisi iptal edilmiş veya işlem için yetkisiz (HTTP 403)';
    } else {
      baseMessage = 'Yetkilendirme hatası (HTTP ${response.statusCode})';
    }

    return _sanitizeString('$baseMessage$codeSuffix');
  }

  /// Sunucu yanıtından yalnızca bilinen, güvenli ve alfanümerik hata kodlarını ayıklar.
  /// Ham veya serbest metinleri KESİNLİKLE kabul etmez.
  String? _extractSafeErrorCode(String body) {
    if (body.isEmpty) return null;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final code = parsed['error'] ?? parsed['code'] ?? parsed['error_code'];
        if (code is String) {
          final trimmed = code.trim();
          // Yalnızca 3-32 karakter uzunluğundaki büyük harf/rakam/altçizgi hata kodları güvenilirdir
          if (RegExp(r'^[A-Z0-9_]{3,32}$').hasMatch(trimmed)) {
            return trimmed;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Metin içindeki token, authorization başlığı veya hassas verileri maskeler
  String _sanitizeString(String text) {
    var result = text;
    if (deviceToken != null && deviceToken!.isNotEmpty) {
      result = result.replaceAll(deviceToken!, '[REDACTED]');
    }
    result = result.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    result = result.replaceAll(
      RegExp(r'(token|secret|password|key)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
      r'$1: [REDACTED]',
    );
    return result;
  }

  /// Sunucu yanıt verisindeki hassas anahtarları filtreler / maskeler
  Map<String, dynamic> _sanitizeResponseData(Map<String, dynamic> data) {
    const sensitiveKeys = {
      'token',
      'device_token',
      'authorization',
      'secret',
      'password',
      'key',
      'auth_token',
      'private_key',
    };

    final sanitized = <String, dynamic>{};
    for (final entry in data.entries) {
      final keyLower = entry.key.toLowerCase();
      if (sensitiveKeys.contains(keyLower)) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is String) {
        sanitized[entry.key] = _sanitizeString(entry.value as String);
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = _sanitizeResponseData(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  /// Kaynakları serbest bırak
  void dispose() {
    _client.close();
  }
}
