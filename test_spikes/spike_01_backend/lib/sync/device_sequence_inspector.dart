import 'package:drift/drift.dart';

import '../db/database.dart';
import 'canonical_payload_hasher.dart';

/// Bir cihazın commit edilmiş `client_seq` kümesi üzerinden kesintisiz High-Water Mark özeti.
class ContiguousHwmSummary {
  /// 1'den başlayarak kesintisiz mevcut en yüksek sıra numarası (`last_committed_client_seq`).
  /// Örneğin {1, 2, 3, 5} için contiguousHwm = 3 olur; 5 olamaz.
  final int contiguousHwm;

  /// Şimdiye dek görülen en büyük commit edilmiş `client_seq` değeri.
  final int maxSeenClientSeq;

  /// Bu cihaz için commit edilmiş toplam sıra sayısı (unique pozitif seq).
  final int committedOperationCount;

  /// `maxSeenClientSeq > contiguousHwm` ise `true` (arada eksik seq var).
  final bool hasSequenceGaps;

  /// En küçükten başlayarak eksik `client_seq` değerlerinden en fazla `maxMissingSample` kadarı.
  final List<int> missingSeqSample;

  const ContiguousHwmSummary({
    required this.contiguousHwm,
    required this.maxSeenClientSeq,
    required this.committedOperationCount,
    required this.hasSequenceGaps,
    required this.missingSeqSample,
  });

  /// Katı FIFO + boşluksuz sırada kabul edilecek bir sonraki yeni `client_seq`.
  int get expectedNextClientSeq => contiguousHwm + 1;
}

/// Bir cihazın Hub üzerindeki salt-okunur sequence ve receipt durumu.
class DeviceSequenceSnapshot {
  final String deviceId;
  final ContiguousHwmSummary hwmSummary;
  final int unverifiableReceiptCount;
  final int latestServerSaleSeq;
  final DateTime? lastCommittedAt;

  const DeviceSequenceSnapshot({
    required this.deviceId,
    required this.hwmSummary,
    required this.unverifiableReceiptCount,
    required this.latestServerSaleSeq,
    required this.lastCommittedAt,
  });
}

/// MARKET MMS — Cihaz Bazlı Kesintisiz High-Water Mark Hesaplayıcı ve Denetleyici.
class DeviceSequenceInspector {
  DeviceSequenceInspector._();

  static ContiguousHwmSummary computeFromSeqs(
    Iterable<int> committedSeqs, {
    int maxMissingSample = 50,
  }) {
    final sortedUnique = committedSeqs.where((s) => s > 0).toSet().toList()
      ..sort();

    if (sortedUnique.isEmpty) {
      return const ContiguousHwmSummary(
        contiguousHwm: 0,
        maxSeenClientSeq: 0,
        committedOperationCount: 0,
        hasSequenceGaps: false,
        missingSeqSample: <int>[],
      );
    }

    var hwm = 0;
    var maxSeen = 0;
    var gapSeen = false;
    var expected = 1;
    final missing = <int>[];

    for (final seq in sortedUnique) {
      if (seq > maxSeen) {
        maxSeen = seq;
      }

      if (!gapSeen && seq == hwm + 1) {
        hwm = seq;
        expected = hwm + 1;
      } else {
        gapSeen = true;
        while (expected < seq && missing.length < maxMissingSample) {
          missing.add(expected);
          expected++;
        }
        expected = seq + 1;
      }
    }

    return ContiguousHwmSummary(
      contiguousHwm: hwm,
      maxSeenClientSeq: maxSeen,
      committedOperationCount: sortedUnique.length,
      hasSequenceGaps: maxSeen > hwm,
      missingSeqSample: List<int>.unmodifiable(missing),
    );
  }

  /// Salt-okunur olarak bir cihazın `processed_operations` ve `sales` görünümünü hesaplar.
  static Future<DeviceSequenceSnapshot> inspectDevice(
    SpikeDatabase db,
    String deviceId,
  ) async {
    final ops = await (db.select(db.processedOperations)
          ..where((o) => o.deviceId.equals(deviceId)))
        .get();

    final seqs = <int>[];
    var unverifiableCount = 0;
    DateTime? latestProcessedAt;

    for (final op in ops) {
      final seq = op.clientSeq;
      if (seq != null && seq > 0) {
        seqs.add(seq);
      }

      final hasValidHash = CanonicalPayloadHasher.isValidSha256Hex(op.requestHash);
      final hasVersion = op.hashVersion != null && op.hashVersion!.trim().isNotEmpty;
      if (!hasValidHash || !hasVersion) {
        unverifiableCount++;
      }

      if (latestProcessedAt == null || op.processedAt.isAfter(latestProcessedAt)) {
        latestProcessedAt = op.processedAt;
      }
    }

    final summary = computeFromSeqs(seqs);

    final maxSaleSeqRow = await db
        .customSelect('SELECT COALESCE(MAX(server_seq), 0) AS m FROM sales;')
        .getSingle();
    final latestServerSaleSeq = (maxSaleSeqRow.data['m'] as int?) ?? 0;

    final deviceRow = await (db.select(db.devices)
          ..where((d) => d.deviceId.equals(deviceId)))
        .getSingleOrNull();

    return DeviceSequenceSnapshot(
      deviceId: deviceId,
      hwmSummary: summary,
      unverifiableReceiptCount: unverifiableCount,
      latestServerSaleSeq: latestServerSaleSeq,
      lastCommittedAt: deviceRow?.lastCommittedAt ?? latestProcessedAt,
    );
  }

  /// Açık transaction içinde cihazın kesintisiz HWM ve max_seen değerini yeniden hesaplar
  /// ve `devices` tablosuna atomik olarak yazar.
  static Future<ContiguousHwmSummary> recomputeAndPersistDeviceHwm(
    SpikeDatabase db,
    String deviceId, {
    required DateTime committedAt,
  }) async {
    final ops = await (db.select(db.processedOperations)
          ..where((o) => o.deviceId.equals(deviceId) & o.clientSeq.isNotNull()))
        .get();

    final summary = computeFromSeqs(ops.map((o) => o.clientSeq!));

    await (db.update(db.devices)..where((d) => d.deviceId.equals(deviceId)))
        .write(
      DevicesCompanion(
        lastCommittedClientSeq: Value(summary.contiguousHwm),
        maxSeenClientSeq: Value(summary.maxSeenClientSeq),
        lastCommittedAt: Value(committedAt),
        lastUsedAt: Value(committedAt),
      ),
    );

    return summary;
  }
}
