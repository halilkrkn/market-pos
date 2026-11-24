import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class HubBackupJobsSnapshot {
  final HubBackupScheduleConfig schedule;
  final String? lastCompletedDateLocal;
  final DateTime? lastCompletedAtUtc;
  final List<HubBackupJobRecord> jobs;

  const HubBackupJobsSnapshot({
    this.schedule = const HubBackupScheduleConfig(),
    this.lastCompletedDateLocal,
    this.lastCompletedAtUtc,
    this.jobs = const [],
  });

  static const empty = HubBackupJobsSnapshot();

  HubBackupJobRecord? get latestJob => jobs.isEmpty ? null : jobs.first;

  HubBackupJobRecord? get latestCompletedUploaded {
    for (final j in jobs) {
      if (j.state == HubBackupJobState.completedUploaded) return j;
    }
    return null;
  }

  HubBackupJobsSnapshot copyWith({
    HubBackupScheduleConfig? schedule,
    String? lastCompletedDateLocal,
    DateTime? lastCompletedAtUtc,
    List<HubBackupJobRecord>? jobs,
  }) =>
      HubBackupJobsSnapshot(
        schedule: schedule ?? this.schedule,
        lastCompletedDateLocal:
            lastCompletedDateLocal ?? this.lastCompletedDateLocal,
        lastCompletedAtUtc: lastCompletedAtUtc ?? this.lastCompletedAtUtc,
        jobs: jobs ?? this.jobs,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'schedule': schedule.toJson(),
        'last_completed_date_local': lastCompletedDateLocal,
        'last_completed_at_utc': lastCompletedAtUtc?.toUtc().toIso8601String(),
        'jobs': jobs.map((j) => j.toJson()).toList(),
      };

  factory HubBackupJobsSnapshot.fromJson(Map<String, dynamic> json) {
    final scheduleMap = json['schedule'];
    final jobsRaw = (json['jobs'] as List?) ?? const [];
    return HubBackupJobsSnapshot(
      schedule: scheduleMap is Map
          ? HubBackupScheduleConfig.fromJson(
              Map<String, dynamic>.from(scheduleMap),
            )
          : const HubBackupScheduleConfig(),
      lastCompletedDateLocal: json['last_completed_date_local'] as String?,
      lastCompletedAtUtc: json['last_completed_at_utc'] is String
          ? DateTime.parse(json['last_completed_at_utc'] as String).toUtc()
          : null,
      jobs: jobsRaw
          .whereType<Map>()
          .map((m) => HubBackupJobRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

/// Faz B-3: Hub yedek iş durumunu atomik `.tmp` + `rename` ile `backup_jobs_state.json`
/// dosyasında saklar.
///
/// S3 (eşzamanlılık): Tüm yazmalar [update] üzerinden dosya yolu başına TEK sıralı
/// kuyrukta yürür. Dönüştürücü her zaman diskteki EN GÜNCEL durumu alır; böylece
/// uzun süren bir işlem (ör. Drive retention silmeleri) beklerken başka bir işlemin
/// yaptığı değişiklik (ör. zamanlama ayarı) eski nesnenin körlemesine yeniden
/// yazılmasıyla kaybolmaz. Dönüştürücü içinde ağ/Drive çağrısı YAPILMAMALIDIR.
class HubBackupStateStore {
  static const String defaultFileName = 'backup_jobs_state.json';
  static const int maxRetainedJobs = 120;

  /// Aynı dosyayı paylaşan tüm örnekler için süreç içi yazma kuyruğu (yol → kuyruk sonu).
  static final Map<String, Future<void>> _writeTails = {};

  final File file;
  final void Function(String message) _log;

  HubBackupStateStore(
    this.file, {
    void Function(String message)? log,
  }) : _log = log ?? _defaultLog;

  static void _defaultLog(String message) => stderr.writeln(message);

  String get _lockKey => file.absolute.path.toLowerCase();

  /// Oku-değiştir-yaz işlemini seri hale getirir; [transform] güncel durumu alır.
  /// [transform] aynı nesneyi döndürürse diske yazılmaz.
  Future<HubBackupJobsSnapshot> update(
    HubBackupJobsSnapshot Function(HubBackupJobsSnapshot current) transform,
  ) {
    final key = _lockKey;
    final previous = _writeTails[key] ?? Future<void>.value();
    final completer = Completer<HubBackupJobsSnapshot>();
    final tail = previous.then((_) async {
      try {
        final current = await load();
        final next = transform(current);
        if (!identical(next, current)) {
          await _write(next);
        }
        completer.complete(next);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    _writeTails[key] = tail;
    tail.whenComplete(() {
      if (identical(_writeTails[key], tail)) {
        _writeTails.remove(key);
      }
    });
    return completer.future;
  }

  Future<HubBackupJobsSnapshot> load() async {
    if (!await file.exists()) return HubBackupJobsSnapshot.empty;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Kök nesne Map değil');
      return HubBackupJobsSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final quarantine = '${file.path}.corrupt_$stamp';
      try {
        await file.rename(quarantine);
      } catch (renameErr) {
        _log(
          '[HubBackupStateStore] Bozuk durum dosyası karantinaya alınamadı (${p.basename(quarantine)}): ${renameErr.runtimeType}',
        );
      }
      _log(
        '[HubBackupStateStore] Bozuk durum dosyası karantinaya alındı (${p.basename(quarantine)}): ${e.runtimeType}',
      );
      return HubBackupJobsSnapshot.empty;
    }
  }

  /// Tüm durumu verilen nesneyle değiştirir (yazma kuyruğu üzerinden).
  ///
  /// UYARI: Önceden okunmuş bir nesneyi geri yazmak, arada yapılan değişiklikleri
  /// ezer. Üretim kodu alan bazlı güncellemeler için [update] / [upsertJob] kullanır.
  Future<void> save(HubBackupJobsSnapshot snapshot) async {
    await update((_) => snapshot);
  }

  Future<void> _write(HubBackupJobsSnapshot snapshot) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final cappedJobs = snapshot.jobs.length > maxRetainedJobs
        ? snapshot.jobs.sublist(0, maxRetainedJobs)
        : snapshot.jobs;
    final trimmed = snapshot.copyWith(jobs: cappedJobs);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(trimmed.toJson()), flush: true);
    try {
      // Windows'ta Dart `rename` hedef dosyanın yerine atomik olarak geçer
      // (MoveFileEx REPLACE_EXISTING); "önce sil" penceresi oluşmaz.
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
  }

  /// Tek bir işi (backupId) güncel durumun üzerine yazar; diğer işler ve zamanlama korunur.
  Future<HubBackupJobsSnapshot> upsertJob(
    HubBackupJobRecord job, {
    HubBackupScheduleConfig? schedule,
    String? lastCompletedDateLocal,
    DateTime? lastCompletedAtUtc,
  }) {
    return update((current) {
      final updatedJobs = <HubBackupJobRecord>[
        job,
        ...current.jobs.where((j) => j.backupId != job.backupId),
      ];
      return current.copyWith(
        schedule: schedule,
        lastCompletedDateLocal: lastCompletedDateLocal,
        lastCompletedAtUtc: lastCompletedAtUtc,
        jobs: updatedJobs,
      );
    });
  }

  /// Yalnızca zamanlama alanını günceller (işler korunur).
  Future<HubBackupJobsSnapshot> updateSchedule(HubBackupScheduleConfig schedule) {
    return update((current) => current.copyWith(schedule: schedule));
  }

  /// Yalnızca [backupIds] içindeki işleri [patch] ile dönüştürür. İş artık yoksa
  /// atlanır; diğer işler ve zamanlama dokunulmadan kalır.
  Future<HubBackupJobsSnapshot> patchJobs(
    Set<String> backupIds,
    HubBackupJobRecord Function(HubBackupJobRecord job) patch,
  ) {
    return update((current) {
      var changed = false;
      final nextJobs = <HubBackupJobRecord>[];
      for (final j in current.jobs) {
        if (backupIds.contains(j.backupId)) {
          final patched = patch(j);
          if (!identical(patched, j)) changed = true;
          nextJobs.add(patched);
        } else {
          nextJobs.add(j);
        }
      }
      return changed ? current.copyWith(jobs: nextJobs) : current;
    });
  }
}
