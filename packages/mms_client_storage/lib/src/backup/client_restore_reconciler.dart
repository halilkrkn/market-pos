import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Restore öncesi canlı veritabanından staging (geri yüklenecek) veritabanına
/// taşınan Outbox/sıra bilgisinin özeti.
class RestoreOutboxReconciliation {
  /// Canlı DB'den staging'e yazılan toplam Outbox satırı (SYNCED dahil).
  final int carriedOverOperations;

  /// Bunlardan Hub'a henüz ulaşmamış (SYNCED olmayan) olanlar.
  final int unsyncedOperations;

  /// Cihaz bazında restore sonrası `current_client_seq` değeri.
  final Map<String, int> clientSeqByDevice;

  const RestoreOutboxReconciliation({
    required this.carriedOverOperations,
    required this.unsyncedOperations,
    required this.clientSeqByDevice,
  });

  static const empty = RestoreOutboxReconciliation(
    carriedOverOperations: 0,
    unsyncedOperations: 0,
    clientSeqByDevice: {},
  );
}

/// Faz 7A — ADR-BAK-03 / DEC-BAK-02 uygulaması.
///
/// Eski bir yedek geri yüklenirken, yedekten sonra oluşmuş Outbox işlemleri
/// (özellikle Hub'a ulaşmamış satışlar) silinmez ve `client_seq` sayacı geriye
/// alınmaz. Canlı DB duraklatılmış (WAL checkpoint + kapalı) iken, swap'tan ÖNCE
/// staging DB üzerinde çalışır; canlı dosyaya yazmaz.
///
/// Kurallar:
/// - Canlı Outbox satırı her zaman staging'deki aynı `operation_id`'li satırın önüne
///   geçer (en güncel durum canlıdadır). İşlemlerin `operation_id`, `payload`,
///   `payload_hash` ve `client_seq` değerleri değiştirilmez.
/// - `current_client_seq` ve `last_synced_seq` = max(staging, canlı).
/// - `last_server_sale_seq` (satış downlink cursor'ı) yedekteki değerinde kalır;
///   böylece yedekten sonraki satışlar Hub'dan yeniden indirilir.
class ClientRestoreReconciler {
  const ClientRestoreReconciler._();

  static RestoreOutboxReconciliation mergeLiveOutboxIntoStaging({
    required File liveDbFile,
    required File stagingDbFile,
  }) {
    if (!liveDbFile.existsSync()) return RestoreOutboxReconciliation.empty;

    final live = sqlite3.open(liveDbFile.path);
    final staging = sqlite3.open(stagingDbFile.path);
    try {
      if (!_hasTable(live, 'outbox_operations') ||
          !_hasTable(staging, 'outbox_operations')) {
        return RestoreOutboxReconciliation.empty;
      }

      final outboxCols = _commonColumns(live, staging, 'outbox_operations');
      final liveOutbox = live.select(
        'SELECT ${outboxCols.join(', ')} FROM outbox_operations ORDER BY client_seq ASC;',
      );
      final hasSyncStates = _hasTable(live, 'client_sync_states') &&
          _hasTable(staging, 'client_sync_states');
      final liveStates = hasSyncStates
          ? live.select('SELECT * FROM client_sync_states;')
          : const <Row>[];

      var unsynced = 0;
      staging.execute('BEGIN IMMEDIATE;');
      try {
        final insert = staging.prepare(
          'INSERT OR REPLACE INTO outbox_operations (${outboxCols.join(', ')}) '
          'VALUES (${List.filled(outboxCols.length, '?').join(', ')});',
        );
        try {
          for (final row in liveOutbox) {
            insert.execute([for (final c in outboxCols) row[c]]);
            if (row['status'] != 'SYNCED') unsynced++;
          }
        } finally {
          insert.close();
        }

        if (hasSyncStates) {
          _mergeSyncStates(staging, liveStates);
        }
        staging.execute('COMMIT;');
      } catch (_) {
        staging.execute('ROLLBACK;');
        rethrow;
      }

      final seqByDevice = <String, int>{};
      if (hasSyncStates) {
        for (final row in staging.select(
          'SELECT device_id, current_client_seq FROM client_sync_states;',
        )) {
          seqByDevice[row['device_id'] as String] = row['current_client_seq'] as int;
        }
      }

      // Staging WAL içeriği ana dosyaya yazılmadan rename edilirse veri kaybolur.
      staging.execute('PRAGMA wal_checkpoint(TRUNCATE);');

      return RestoreOutboxReconciliation(
        carriedOverOperations: liveOutbox.length,
        unsyncedOperations: unsynced,
        clientSeqByDevice: seqByDevice,
      );
    } finally {
      live.close();
      staging.close();
    }
  }

  static void _mergeSyncStates(Database staging, List<Row> liveStates) {
    final stagingCols = _columns(staging, 'client_sync_states');
    for (final state in liveStates) {
      final deviceId = state['device_id'] as String;
      final liveSeq = (state['current_client_seq'] as int?) ?? 0;
      final liveSynced = (state['last_synced_seq'] as int?) ?? 0;
      final pendingSession = state['pending_sync_session_id'];

      final exists = staging.select(
        'SELECT 1 FROM client_sync_states WHERE device_id = ?;',
        [deviceId],
      ).isNotEmpty;

      if (exists) {
        staging.execute(
          'UPDATE client_sync_states SET '
          'current_client_seq = MAX(current_client_seq, ?), '
          'last_synced_seq = MAX(last_synced_seq, ?)'
          '${stagingCols.contains('pending_sync_session_id') ? ', pending_sync_session_id = ?' : ''} '
          'WHERE device_id = ?;',
          [
            liveSeq,
            liveSynced,
            if (stagingCols.contains('pending_sync_session_id')) pendingSession,
            deviceId,
          ],
        );
      } else {
        // Yedekte bu cihazın sayaç satırı yok: canlı sayaç taşınır; downlink
        // cursor'ı sıfırdan başlar (tüm satış geçmişi Hub'dan yeniden indirilir).
        final cols = state.keys.where(stagingCols.contains).toList();
        final values = [
          for (final c in cols)
            if (c == 'last_server_sale_seq') 0 else if (c == 'last_sales_sync_at') null else state[c],
        ];
        staging.execute(
          'INSERT INTO client_sync_states (${cols.join(', ')}) '
          'VALUES (${List.filled(cols.length, '?').join(', ')});',
          values,
        );
      }
    }

    // Kendini onarma: sayaç hiçbir zaman Outbox'taki en büyük sıranın gerisinde kalamaz.
    staging.execute(
      'UPDATE client_sync_states SET current_client_seq = MAX(current_client_seq, '
      'COALESCE((SELECT MAX(o.client_seq) FROM outbox_operations o '
      'WHERE o.device_id = client_sync_states.device_id), 0));',
    );
  }

  static bool _hasTable(Database db, String table) => db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;",
        [table],
      ).isNotEmpty;

  static Set<String> _columns(Database db, String table) => db
      .select("PRAGMA table_info('$table');")
      .map((r) => r['name'] as String)
      .toSet();

  static List<String> _commonColumns(Database a, Database b, String table) {
    final bCols = _columns(b, table);
    return _columns(a, table).where(bCols.contains).toList();
  }
}
