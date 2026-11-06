import 'package:shelf/shelf.dart';

/// Wildcard (*) yerine yalnızca yerel loopback origin'lerine izin veren güvenli CORS Middleware'i.
Middleware createSecureCorsMiddleware() {
  const allowedOrigins = [
    'http://localhost',
    'http://127.0.0.1',
    'https://localhost',
    'https://127.0.0.1',
  ];

  return (Handler innerHandler) {
    return (Request request) async {
      final origin = request.headers['origin'];

      // Preflight (OPTIONS) istekleri
      if (request.method == 'OPTIONS') {
        final headers = <String, String>{
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
        };

        if (origin != null && allowedOrigins.any((allowed) => origin.startsWith(allowed))) {
          headers['Access-Control-Allow-Origin'] = origin;
          headers['Access-Control-Allow-Credentials'] = 'true';
        }

        return Response.ok('', headers: headers);
      }

      final response = await innerHandler(request);

      if (origin != null && allowedOrigins.any((allowed) => origin.startsWith(allowed))) {
        return response.change(headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Credentials': 'true',
        });
      }

      // Harici veya yetkisiz origin ise kesinlikle Access-Control-Allow-Origin ekleme (Wildcard * YOK!)
      return response;
    };
  };
}

