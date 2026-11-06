import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../db/write_queue.dart';

/// RAM'de tutulan teslimat öğesi
class DeliveryItem {
  final String sessionId;
  final String deviceId;
  String rawToken;
  final Uint8List tokenSha256;
  final DateTime deliveredAt;
  final DateTime expiresAt;
  bool isAcked;

  DeliveryItem({
    required this.sessionId,
    required this.deviceId,
    required this.rawToken,
    required this.tokenSha256,
    required this.deliveredAt,
    required this.expiresAt,
    this.isAcked = false,
  });
}

/// S-4: Ham token'ın veritabanına yazılmadan, yalnızca RAM'de 120 saniyelik Kurtarma TTL'i ile
/// tutulmasını, imzalı ACK teyidiyle silinmesini ve zaman aşımı durumunda cihazın iptalini yöneten tampon.
class PairingDeliveryBuffer {
  static const Duration deliveryTtl = Duration(seconds: 120);

  final Map<String, DeliveryItem> _buffer = {};

  /// Token'ı teslimat tamponuna ekler (Sadece RAM).
  void store({
    required String sessionId,
    required String deviceId,
    required String rawToken,
  }) {
    final now = DateTime.now();
    final tokenBytes = utf8.encode(rawToken);
    final tokenSha256 = Uint8List.fromList(sha256.convert(tokenBytes).bytes);

    _buffer[sessionId] = DeliveryItem(
      sessionId: sessionId,
      deviceId: deviceId,
      rawToken: rawToken,
      tokenSha256: tokenSha256,
      deliveredAt: now,
      expiresAt: now.add(deliveryTtl),
      isAcked: false,
    );
  }

  /// Aktif ve süresi dolmamış ham token'ı döndürür (Tekrarlayan poll istekleri için).
  String? getRawToken(String sessionId) {
    final item = _buffer[sessionId];
    if (item == null) return null;
    if (DateTime.now().isAfter(item.expiresAt) || item.isAcked) {
      return null;
    }
    return item.rawToken;
  }

  /// Oturuma ait token'ın SHA-256 özetini döner (ACK çerçeve doğrulaması için).
  Uint8List? getTokenSha256(String sessionId) {
    final item = _buffer[sessionId];
    if (item == null) return null;
    if (DateTime.now().isAfter(item.expiresAt) || item.isAcked) {
      return null;
    }
    return item.tokenSha256;
  }

  /// İstemciden gelen ACK'yı teyit eder ve onaylar.
  Future<bool> acknowledge({
    required String sessionId,
    required SpikeDatabase db,
    required WriteQueue writeQueue,
  }) async {
    final item = _buffer[sessionId];
    if (item == null) return false;
    if (DateTime.now().isAfter(item.expiresAt)) {
      return false;
    }

    item.isAcked = true;
    item.rawToken = ''; // Bellek referansını temizle
    _buffer.remove(sessionId);

    // Veritabanında cihazı confirmed yap
    await writeQueue.enqueue(() async {
      await db.transaction(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(item.deviceId))).write(
          const DevicesCompanion(
            isConfirmed: Value(true),
          ),
        );

        await db.into(db.deviceAuditLogs).insert(
          DeviceAuditLogsCompanion(
            deviceId: Value(item.deviceId),
            action: const Value('PAIRING_DELIVERY_CONFIRMED'),
            details: Value('Session: $sessionId, Delivery acknowledged and confirmed.'),
          ),
        );
      });
    });

    return true;
  }

  /// Süresi dolan (120 sn ACK gelmeyen) tampon kayıtlarını temizler ve cihazları iptal eder.
  Future<int> cleanUpExpired({
    required SpikeDatabase db,
    required WriteQueue writeQueue,
  }) async {
    final now = DateTime.now();
    final expiredSessions = <String>[];

    for (final entry in _buffer.entries) {
      if (now.isAfter(entry.value.expiresAt) && !entry.value.isAcked) {
        expiredSessions.add(entry.key);
      }
    }

    for (final sessionId in expiredSessions) {
      final item = _buffer.remove(sessionId);
      if (item != null && !item.isAcked) {
        item.rawToken = ''; // RAM temizliği
        await writeQueue.enqueue(() async {
          await db.transaction(() async {
            await (db.update(db.devices)..where((d) => d.deviceId.equals(item.deviceId))).write(
              const DevicesCompanion(
                isActive: Value(false),
              ),
            );

            await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(item.deviceId),
                action: const Value('PAIRING_DELIVERY_TIMEOUT'),
                details: Value('Session: $sessionId, 120s ACK timeout. Device deactivated.'),
              ),
            );
          });
        });
      }
    }

    return expiredSessions.length;
  }

  /// Sunucu açılışında yarım kalmış unconfirmed cihazları temizler (Startup Reconcile).
  static Future<int> startupReconcile({
    required SpikeDatabase db,
    required WriteQueue writeQueue,
  }) async {
    return await writeQueue.enqueue(() async {
      var cleanedCount = 0;
      await db.transaction(() async {
        final unconfirmedDevices = await (db.select(db.devices)
              ..where((d) => d.isConfirmed.equals(false) & d.isActive.equals(true)))
            .get();

        for (final device in unconfirmedDevices) {
          await (db.update(db.devices)..where((d) => d.deviceId.equals(device.deviceId))).write(
            const DevicesCompanion(
              isActive: Value(false),
            ),
          );

          await db.into(db.deviceAuditLogs).insert(
            DeviceAuditLogsCompanion(
              deviceId: Value(device.deviceId),
              action: const Value('PAIRING_CRASH_UNCONFIRMED_CLEANUP'),
              details: const Value('Server startup: unconfirmed device automatically cleaned up.'),
            ),
          );
          cleanedCount++;
        }
      });
      return cleanedCount;
    });
  }

  /// Test amaçlı bellek temizleme
  void clear() {
    _buffer.clear();
  }
}
