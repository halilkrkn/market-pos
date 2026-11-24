/// Merkezi Hub Google Drive saklama politikası ve 7 günlük yerel önbellek ayrımı (`OV-05`).
class HubBackupRetentionCandidate {
  final String backupId;
  final DateTime createdAtUtc;
  final bool isCompletedUploaded;
  final String? driveFileId;
  final String? localFilePath;

  const HubBackupRetentionCandidate({
    required this.backupId,
    required this.createdAtUtc,
    required this.isCompletedUploaded,
    this.driveFileId,
    this.localFilePath,
  });

  bool get hasValidDriveCopy =>
      isCompletedUploaded && driveFileId != null && driveFileId!.isNotEmpty;
}

class HubBackupRetentionPlan {
  final List<String> retainIds;
  final List<String> pruneIds;

  const HubBackupRetentionPlan({
    required this.retainIds,
    required this.pruneIds,
  });
}

class HubBackupRetentionPolicy {
  final int driveDailyRetentionDays;
  final int driveMonthlyCount;
  final int localCacheRetentionDays;

  const HubBackupRetentionPolicy({
    this.driveDailyRetentionDays = 30,
    this.driveMonthlyCount = 12,
    this.localCacheRetentionDays = 7,
  });

  /// Drive arşivi: Son 30 gün günlük + ötesinde en fazla 12 farklı takvim ayı
  /// (her ayın en güncel `COMPLETED_UPLOADED` yedeği) + SERT DEĞİŞMEZ:
  /// Geçerli en az 1 `COMPLETED_UPLOADED` Drive yedeği asla silinmez.
  HubBackupRetentionPlan evaluateDriveRetention(
    List<HubBackupRetentionCandidate> candidates, {
    required DateTime nowUtc,
  }) {
    final utcNow = nowUtc.toUtc();
    final dailyCutoff = utcNow.subtract(Duration(days: driveDailyRetentionDays));

    final valid = candidates.where((c) => c.hasValidDriveCopy).toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));

    if (valid.isEmpty) {
      return const HubBackupRetentionPlan(retainIds: [], pruneIds: []);
    }

    final retained = <String>{};
    final monthlyPicks = <String, HubBackupRetentionCandidate>{};

    for (final c in valid) {
      if (!c.createdAtUtc.isBefore(dailyCutoff)) {
        retained.add(c.backupId);
      } else {
        final ym = _yearMonthKey(c.createdAtUtc);
        monthlyPicks.putIfAbsent(ym, () => c);
      }
    }

    final sortedMonths = monthlyPicks.values.toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    for (final pick in sortedMonths.take(driveMonthlyCount)) {
      retained.add(pick.backupId);
    }

    // SERT DEĞİŞMEZ: En az 1 geçerli COMPLETED_UPLOADED yedek her zaman korunur
    if (retained.isEmpty) {
      retained.add(valid.first.backupId);
    }

    final prune = valid
        .where((c) => !retained.contains(c.backupId))
        .map((c) => c.backupId)
        .toList();

    return HubBackupRetentionPlan(
      retainIds: valid
          .where((c) => retained.contains(c.backupId))
          .map((c) => c.backupId)
          .toList(),
      pruneIds: prune,
    );
  }

  /// Yerel Hub `.mmsbak` önbellek temizliği (`OV-05`): Drive arşivinden bağımsız
  /// olarak 7 gün tutar; ancak henüz Drive'a yüklenmemiş hiçbir yedeği ve en son
  /// geçerli yedeği asla silmez.
  HubBackupRetentionPlan evaluateLocalCacheRetention(
    List<HubBackupRetentionCandidate> candidates, {
    required DateTime nowUtc,
  }) {
    final utcNow = nowUtc.toUtc();
    final cacheCutoff = utcNow.subtract(Duration(days: localCacheRetentionDays));

    final withLocal = candidates
        .where((c) => c.localFilePath != null && c.localFilePath!.isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));

    if (withLocal.isEmpty) {
      return const HubBackupRetentionPlan(retainIds: [], pruneIds: []);
    }

    final retained = <String>{};
    String? latestCompletedId;
    for (final c in withLocal) {
      if (!c.isCompletedUploaded) {
        // Yüklenmemiş veya bekleyen yerel paket asla önbellekten silinmez.
        retained.add(c.backupId);
        continue;
      }
      latestCompletedId ??= c.backupId;
      if (!c.createdAtUtc.isBefore(cacheCutoff)) {
        retained.add(c.backupId);
      }
    }

    if (latestCompletedId != null) {
      retained.add(latestCompletedId);
    }

    final prune = withLocal
        .where((c) => !retained.contains(c.backupId))
        .map((c) => c.backupId)
        .toList();

    return HubBackupRetentionPlan(
      retainIds: withLocal
          .where((c) => retained.contains(c.backupId))
          .map((c) => c.backupId)
          .toList(),
      pruneIds: prune,
    );
  }

  String _yearMonthKey(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}';
  }
}
