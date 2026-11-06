import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

class PayloadTooLargeException implements Exception {
  final String message;
  PayloadTooLargeException([this.message = 'İstek gövdesi izin verilen sınırı aştı.']);

  @override
  String toString() => message;
}

/// Request body boyutunu hem Content-Length header'ı hem de stream okuma sırasında sınırlandıran Shelf Middleware.
/// Varsayılan sınır: 2 MB (2 * 1024 * 1024 byte).
Middleware createBodyLimitMiddleware({int maxBytes = 2 * 1024 * 1024}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // 1. Content-Length Header Kontrolü (Hızlı reddetme)
      final contentLength = request.contentLength;
      if (contentLength != null && contentLength > maxBytes) {
        return Response(
          413,
          body: jsonEncode({
            'error': 'PAYLOAD_TOO_LARGE',
            'code': 'ERR_PAYLOAD_TOO_LARGE',
            'message': 'İstek gövdesi boyutu maksimum ${maxBytes ~/ (1024 * 1024)} MB olabilir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 2. Stream Okuma Kontrolü (Chunked veya sahte header'lara karşı gövde akışını sayaçla sarmalama)
      Stream<List<int>> transformStream(Stream<List<int>> source) async* {
        var totalBytes = 0;
        await for (final chunk in source) {
          totalBytes += chunk.length;
          if (totalBytes > maxBytes) {
            throw PayloadTooLargeException(
              'İstek gövdesi akış sırasında $maxBytes byte sınırını aştı.',
            );
          }
          yield chunk;
        }
      }

      final limitedRequest = request.change(body: transformStream(request.read()));

      try {
        return await innerHandler(limitedRequest);
      } on PayloadTooLargeException catch (e) {
        return Response(
          413,
          body: jsonEncode({
            'error': 'PAYLOAD_TOO_LARGE',
            'code': 'ERR_PAYLOAD_TOO_LARGE',
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  };
}

