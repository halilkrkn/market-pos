import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import '../db/database.dart';
import '../db/write_queue.dart';
import 'pepper_manager.dart';
import 'token_manager.dart';

Middleware createAuthMiddleware({
  required SpikeDatabase db,
  required bool Function() isDraining,
  required PepperManager pepperManager,
  WriteQueue? writeQueue,
  bool requireTls = false,
  List<String> publicPaths = const ['/health'],
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // 1. Draining kontrolü (Servis kapanıyorsa istekleri reddet)
      if (isDraining()) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'SERVICE_DRAINING',
            'message': 'Windows Service kapanıyor, yeni istek kabul edilmiyor.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 2. Açık / Public yollar (Health check vb.)
      final reqPath = request.url.path;
      final normalizedPath = reqPath.startsWith('/') ? reqPath : '/$reqPath';
      if (publicPaths.contains(reqPath) || publicPaths.contains(normalizedPath)) {
        return innerHandler(request);
      }

      // 3. TLS Zorunluluğu Kontrolü (S-3: Hassas API ve Token İletişimi Şifresiz HTTP'ye Kapatılır)
      if (requireTls && request.requestedUri.scheme != 'https') {
        return Response(
          426,
          body: jsonEncode({
            'error': 'UPGRADE_REQUIRED',
            'code': 'ERR_TLS_REQUIRED',
            'message': 'Hassas API ve kimlik doğrulama işlemleri yalnızca TLS 1.3 / HTTPS üzerinden kabul edilir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 3. Authorization Header kontrolü
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'message':
                'Erişim için geçerli bir Bearer Device Token gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = authHeader.substring(7).trim();
      if (token.isEmpty) {
        return Response(
          401,
          body: jsonEncode(
              {'error': 'INVALID_TOKEN', 'message': 'Token boş olamaz.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // 4. Veritabanından cihazı ve yetkisini doğrula (S-2 SHA-256 Hash + Salt + Pepper)
      final activePepper = pepperManager.pepper;
      final allDevices = await db.select(db.devices).get();
      Device? matchedDevice;

      for (final device in allDevices) {
        if (TokenManager.verifyToken(
          rawToken: token,
          salt: device.salt,
          expectedHash: device.tokenHash,
          pepper: activePepper,
        )) {
          matchedDevice = device;
          break;
        }
      }

      if (matchedDevice == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'DEVICE_NOT_FOUND',
            'message': 'Bu token ile eşleşen yetkili bir cihaz bulunamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!matchedDevice.isActive) {
        return Response(
          403,
          body: jsonEncode({
            'error': 'DEVICE_REVOKED',
            'message':
                'Bu cihazın Master Hub erişim yetkisi işletme sahibi tarafından iptal edilmiştir.',
            'device_id': matchedDevice.deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!matchedDevice.isConfirmed) {
        return Response(
          403,
          body: jsonEncode({
            'error': 'DEVICE_NOT_CONFIRMED',
            'code': 'ERR_DEVICE_NOT_CONFIRMED',
            'message':
                'Cihazın eşleştirme ACK teyidi henüz tamamlanmamıştır. Normal API erişimi engellendi.',
            'device_id': matchedDevice.deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (matchedDevice.expiresAt != null &&
          DateTime.now().isAfter(matchedDevice.expiresAt!)) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'TOKEN_EXPIRED',
            'message':
                'Cihaz token süresi dolmuştur. Lütfen yeniden eşleştirin veya yenileyin.',
            'device_id': matchedDevice.deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // lastUsedAt güncellemesi
      if (writeQueue != null && !isDraining()) {
        writeQueue.enqueue(() async {
          await (db.update(db.devices)..where((d) => d.deviceId.equals(matchedDevice!.deviceId)))
              .write(DevicesCompanion(lastUsedAt: Value(DateTime.now())));
        }).catchError((_) {});
      }

      // 5. Cihaz kimliğini istek bağlamına (context) ekle ve devam et
      final updatedRequest = request.change(context: {
        'authenticated_device_id': matchedDevice.deviceId,
        'authenticated_device_name': matchedDevice.name,
        'authenticated_device_role': matchedDevice.role,
      });

      return innerHandler(updatedRequest);
    };
  };
}
