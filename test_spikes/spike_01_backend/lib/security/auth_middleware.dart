import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import '../db/database.dart';
import '../db/write_queue.dart';
import 'pepper_manager.dart';
import 'token_manager.dart';

Middleware createAuthMiddleware({
  SpikeDatabase? db,
  SpikeDatabase Function()? dbProvider,
  required bool Function() isDraining,
  required PepperManager pepperManager,
  WriteQueue? writeQueue,
  bool requireTls = false,
  String expectedTenantId = 'default-tenant',
  String expectedStoreId = 'default-store',
  bool requireTenantStoreHeaders = false,
  List<String> strictTenantStorePaths = const [
    '/api/v1/devices/me',
    '/api/v1/sync/device-state',
    '/api/v1/sync/receipts',
    '/api/v1/sync/live-drive-config',
  ],
  List<String> storeDataPrefixes = const [
    '/api/v1/sales',
    '/api/v1/products',
    '/api/v1/sync/',
    '/api/v1/stock/',
  ],
  List<String> publicPaths = const ['/health'],
  List<String> bearerOrAdminPaths = const [],
}) {
  if (db == null && dbProvider == null) {
    throw ArgumentError('createAuthMiddleware için db veya dbProvider zorunludur.');
  }
  final resolveDb = dbProvider ?? () => db!;
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

      // 3. Authorization Header kontrolü (veya bearerOrAdminPaths üzerinde admin secret devri)
      final authHeader = request.headers['authorization'];
      final hasAdminHeader = (request.headers['x-admin-secret']?.trim().isNotEmpty ?? false) ||
          (request.headers['x-mms-admin-secret']?.trim().isNotEmpty ?? false);
      if ((bearerOrAdminPaths.contains(reqPath) ||
              bearerOrAdminPaths.contains(normalizedPath)) &&
          hasAdminHeader &&
          (authHeader == null || !authHeader.startsWith('Bearer '))) {
        return innerHandler(request);
      }
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
      final activeDb = resolveDb();
      final activePepper = pepperManager.pepper;
      final allDevices = await activeDb.select(activeDb.devices).get();
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
          final targetDb = resolveDb();
          await (targetDb.update(targetDb.devices)
                ..where((d) => d.deviceId.equals(matchedDevice!.deviceId)))
              .write(DevicesCompanion(lastUsedAt: Value(DateTime.now())));
        }).catchError((_) {});
      }

      // 5. BK-02.1 Pilot Tenant / Store Kimlik Doğrulaması (Mağaza Verisi İzolasyonu)
      final isStrictPath = strictTenantStorePaths.contains(normalizedPath);
      final isStoreDataRoute =
          isStrictPath || storeDataPrefixes.any((prefix) => normalizedPath.startsWith(prefix));
      final rawTenantHeader = request.headers['x-mms-tenant-id'];
      final rawStoreHeader = request.headers['x-mms-store-id'];
      final hasAnyTenantStoreHeader =
          rawTenantHeader != null || rawStoreHeader != null;

      if (hasAnyTenantStoreHeader) {
        final cleanTenant = rawTenantHeader?.trim();
        final cleanStore = rawStoreHeader?.trim();
        if (cleanTenant != expectedTenantId || cleanStore != expectedStoreId) {
          return Response(
            403,
            body: jsonEncode({
              'error': 'FORBIDDEN',
              'code': 'ERR_TENANT_STORE_MISMATCH',
              'message':
                  'Tenant veya şube kimliği bu Master Hub ile eşleşmiyor.',
              'expected_tenant_id': expectedTenantId,
              'expected_store_id': expectedStoreId,
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      } else if (isStoreDataRoute &&
          (isStrictPath || requireTenantStoreHeaders)) {
        return Response(
          403,
          body: jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_TENANT_STORE_REQUIRED',
            'message':
                'Mağaza verisine erişim için X-MMS-Tenant-Id ve X-MMS-Store-Id başlıkları zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // 6. Cihaz kimliğini ve doğrulanmış mağaza bağlamını istek context'ine ekle ve devam et
      final updatedRequest = request.change(context: {
        'authenticated_device_id': matchedDevice.deviceId,
        'authenticated_device_name': matchedDevice.name,
        'authenticated_device_role': matchedDevice.role,
        'authenticated_tenant_id': expectedTenantId,
        'authenticated_store_id': expectedStoreId,
      });

      return innerHandler(updatedRequest);
    };
  };
}
