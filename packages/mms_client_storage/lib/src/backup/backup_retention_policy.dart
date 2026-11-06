import 'backup_manifest.dart';
import 'backup_storage_provider.dart';

class RetentionPolicy {
  final int dailyRetentionDays;
  final int monthlyRetentionMonths;

  const RetentionPolicy({
    this.dailyRetentionDays = 30,
    this.monthlyRetentionMonths = 12,
  });
}

class RetentionPrunePlan {
  final List<String> retainedDailyIds;
  final List<String> retainedMonthlyIds;
  final List<String> expiredIdsToPrune;

  const RetentionPrunePlan({
    required this.retainedDailyIds,
    required this.retainedMonthlyIds,
    required this.expiredIdsToPrune,
  });
}

/// S5A-4: 30 günlük standart günlük saklama ve 12 aylık aylık arşiv saklama politikası yöneticisi
class RetentionPolicyManager {
  final RetentionPolicy policy;

  const RetentionPolicyManager({
    this.policy = const RetentionPolicy(),
  });

  /// Verilen yedek listesi üzerinde saklama politikasını simüle eder ve temizleme planı döner
  RetentionPrunePlan planPruning(
    List<BackupPackageInfo> backups, {
    DateTime? now,
  }) {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final dailyCutoff = effectiveNow.subtract(Duration(days: policy.dailyRetentionDays));
    final monthlyCutoff = effectiveNow.subtract(Duration(days: policy.monthlyRetentionMonths * 30));

    final retainedDaily = <String>{};
    final retainedMonthly = <String>{};
    final toPrune = <String>{};

    // Kronolojik sırala (eskiden yeniye)
    final sortedBackups = List<BackupPackageInfo>.from(backups)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Her ayın en eski yedeğini belirlemek için (Yıl-Ay anahtarı)
    final monthlyCandidates = <String, BackupPackageInfo>{};

    for (final backup in sortedBackups) {
      final key = '${backup.timestamp.year}-${backup.timestamp.month.toString().padLeft(2, '0')}';
      if (!monthlyCandidates.containsKey(key)) {
        monthlyCandidates[key] = backup;
      }
    }

    final monthlyIds = monthlyCandidates.values.map((b) => b.backupId).toSet();

    for (final backup in sortedBackups) {
      final id = backup.backupId;
      final ts = backup.timestamp;
      final isMonthly = monthlyIds.contains(id) || backup.manifest.isMonthlyArchive;

      if (!ts.isBefore(dailyCutoff)) {
        // 1. Son 30 gün içindeki tüm yedekler korunur (Günlük saklama)
        retainedDaily.add(id);
      } else if (isMonthly && !ts.isBefore(monthlyCutoff)) {
        // 2. 30 günden eski ama 12 aydan yeni olan aylık arşiv yedekleri korunur
        retainedMonthly.add(id);
      } else {
        // 3. 30 günden eski günlük yedekler ve 12 aydan eski tüm arşivler temizlenir
        toPrune.add(id);
      }
    }

    return RetentionPrunePlan(
      retainedDailyIds: retainedDaily.toList(),
      retainedMonthlyIds: retainedMonthly.toList(),
      expiredIdsToPrune: toPrune.toList(),
    );
  }

  /// Saklama politikasına göre süresi dolmuş eski yedekleri depolama alanından siler
  Future<List<String>> executePruning(
    BackupStorageProvider storage, {
    String? tenantId,
    String? deviceId,
    DatabaseType? databaseType,
    DateTime? now,
  }) async {
    final allBackups = await storage.listBackups(
      tenantId: tenantId,
      deviceId: deviceId,
      databaseType: databaseType,
    );

    final plan = planPruning(allBackups, now: now);
    final prunedIds = <String>[];

    for (final id in plan.expiredIdsToPrune) {
      try {
        await storage.deleteBackup(id);
        prunedIds.add(id);
      } catch (_) {
        // Tekil silme hataları diğerlerinin silinmesini durdurmaz
      }
    }

    return prunedIds;
  }
}

