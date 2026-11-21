import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/security/secure_token_store.dart';
import 'client_backup_service.dart';

/// Faz 3 — İstemci (Windows kasa / Android) zamanlanmış yerel yedek ayarları.
///
/// Sorumluluk ayrımı: Merkezi otorite Windows Hub'dır ve kendi `market_master.db`
/// yedeğini servis içinde alır. İstemci yedeği; Hub'a henüz ulaşmamış Outbox
/// işlemlerini ve yerel ayarları korur. Android'de zamanlayıcı yalnızca uygulama
/// açıkken çalışır (açılışta/öne gelişte gecikmiş yedek hemen alınır).
class ClientBackupScheduleSettings {
  static const List<int> supportedIntervalHours = [6, 12, 24];

  final bool enabled;
  final int intervalHours;

  const ClientBackupScheduleSettings({required this.enabled, required this.intervalHours});

  static const disabled = ClientBackupScheduleSettings(enabled: false, intervalHours: 24);

  BackupSchedulePolicy toPolicy() => enabled
      ? BackupSchedulePolicy(interval: Duration(hours: intervalHours))
      : BackupSchedulePolicy.disabled;

  Map<String, dynamic> toJson() => {'version': 1, 'enabled': enabled, 'interval_hours': intervalHours};

  factory ClientBackupScheduleSettings.fromJson(Map<String, dynamic> json) {
    final hours = json['interval_hours'];
    return ClientBackupScheduleSettings(
      enabled: json['enabled'] == true,
      intervalHours: hours is int && supportedIntervalHours.contains(hours) ? hours : 24,
    );
  }
}

/// Ayarları JSON dosyasında atomik saklar. Parola BURADA TUTULMAZ (güvenli depodadır).
class ClientBackupScheduleSettingsStore {
  final File file;
  ClientBackupScheduleSettingsStore(this.file);

  Future<ClientBackupScheduleSettings> load() async {
    if (!await file.exists()) return ClientBackupScheduleSettings.disabled;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return ClientBackupScheduleSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on FormatException catch (e) {
      stderr.writeln('[BackupSchedule] Ayar dosyası okunamadı, otomatik yedek kapalı kabul edildi: ${e.message}');
    }
    return ClientBackupScheduleSettings.disabled;
  }

  Future<void> save(ClientBackupScheduleSettings settings) async {
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class BackupScheduleViewState {
  final ClientBackupScheduleSettings settings;
  final BackupScheduleState scheduleState;
  final bool isRunning;
  final bool isSchedulerActive;

  const BackupScheduleViewState({
    required this.settings,
    required this.scheduleState,
    this.isRunning = false,
    this.isSchedulerActive = false,
  });

  static const initial = BackupScheduleViewState(
    settings: ClientBackupScheduleSettings.disabled,
    scheduleState: BackupScheduleState.empty,
  );

  bool get isOverdue => settings.toPolicy().isOverdue(state: scheduleState, now: DateTime.now().toUtc());

  BackupScheduleViewState copyWith({
    ClientBackupScheduleSettings? settings,
    BackupScheduleState? scheduleState,
    bool? isRunning,
    bool? isSchedulerActive,
  }) =>
      BackupScheduleViewState(
        settings: settings ?? this.settings,
        scheduleState: scheduleState ?? this.scheduleState,
        isRunning: isRunning ?? this.isRunning,
        isSchedulerActive: isSchedulerActive ?? this.isSchedulerActive,
      );
}

/// Zamanlanmış yedeklemeyi yöneten uygulama katmanı denetleyicisi.
class BackupScheduleController extends StateNotifier<BackupScheduleViewState> {
  /// Otomatik yedek parolasının DPAPI (Windows) / Android Keystore anahtarı.
  static const String passwordSecretKey = 'backup_schedule_password_v1';

  final ClientBackupService backupService;
  final SecureTokenStore secureStore;
  final ClientBackupScheduleSettingsStore settingsStore;
  final BackupScheduleStateStore stateStore;
  final Duration checkInterval;
  final Future<void> Function(BackupResult result)? afterSuccess;

  late final ScheduledBackupRunner _runner = ScheduledBackupRunner(
    readPolicy: () => state.settings.toPolicy(),
    stateStore: stateStore,
    createBackup: _createScheduledBackup,
    pruneExpired: () => backupService.pruneExpiredBackups(state.settings.toPolicy().retention),
    afterSuccess: afterSuccess,
  );
  Timer? _timer;
  Future<void>? _pendingTick;

  BackupScheduleController({
    required this.backupService,
    required this.secureStore,
    required this.settingsStore,
    required this.stateStore,
    this.checkInterval = const Duration(minutes: 15),
    this.afterSuccess,
  }) : super(BackupScheduleViewState.initial);

  Future<void> initialize() async {
    final settings = await settingsStore.load();
    final schedule = await stateStore.load();
    if (!mounted) return;
    state = state.copyWith(settings: settings, scheduleState: schedule);
    if (settings.enabled) _startScheduler();
  }

  Future<void> enable({required int intervalHours, required String password}) async {
    if (!ClientBackupScheduleSettings.supportedIntervalHours.contains(intervalHours)) {
      throw BackupException(
        'ERR_UNSUPPORTED_INTERVAL',
        'Desteklenen yedekleme sıklıkları: ${ClientBackupScheduleSettings.supportedIntervalHours.join(', ')} saat.',
      );
    }
    if (password.trim().length < 8) {
      throw const BackupException('ERR_WEAK_PASSWORD', 'Yedekleme parolası en az 8 karakter olmalıdır.');
    }
    await secureStore.saveSecret(passwordSecretKey, password);
    final settings = ClientBackupScheduleSettings(enabled: true, intervalHours: intervalHours);
    await settingsStore.save(settings);
    if (!mounted) return;
    state = state.copyWith(settings: settings);
    await _stopScheduler();
    _startScheduler();
  }

  Future<void> disable() async {
    await _stopScheduler();
    await settingsStore.save(ClientBackupScheduleSettings.disabled);
    await secureStore.deleteSecret(passwordSecretKey);
    if (!mounted) return;
    state = state.copyWith(settings: ClientBackupScheduleSettings.disabled, isSchedulerActive: false);
  }

  /// Kayıtlı parola ile hemen yedek alır (Owner'ın "Şimdi Yedekle" komutu).
  Future<BackupRunRecord?> runNow() async {
    if (!state.settings.enabled) return null;
    _setRunning(true);
    try {
      final record = await _runner.runNow(trigger: BackupTrigger.manual);
      await _refreshState();
      return record;
    } finally {
      _setRunning(false);
    }
  }

  /// Test ve UI için: devam eden zamanlayıcı turunun bitmesini bekler.
  Future<void> waitForIdle() async {
    while (_pendingTick != null) {
      await _pendingTick;
    }
  }

  Future<BackupResult> _createScheduledBackup() async {
    final String? password;
    try {
      password = await secureStore.readSecret(passwordSecretKey);
    } on SecureStorageException catch (e) {
      throw BackupException('ERR_SECURE_STORE', 'Otomatik yedek parolası güvenli depodan okunamadı: ${e.message}');
    }
    if (password == null || password.isEmpty) {
      throw const BackupException(
        'ERR_SCHEDULE_PASSWORD_MISSING',
        'Otomatik yedek parolası güvenli depoda bulunamadı; otomatik yedeklemeyi parolayla yeniden etkinleştirin.',
      );
    }
    return backupService.createEncryptedBackup(password: password);
  }

  void _startScheduler() {
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _tick());
    if (mounted) state = state.copyWith(isSchedulerActive: true);
    _tick(); // Açılışta / etkinleştirmede gecikmiş yedek hemen alınır.
  }

  Future<void> _stopScheduler() async {
    _timer?.cancel();
    _timer = null;
    await waitForIdle();
  }

  Future<BackupRunRecord?> _tick() {
    final completer = Completer<void>();
    final previous = _pendingTick;
    _pendingTick = completer.future;
    return () async {
      if (previous != null) await previous;
      _setRunning(true);
      try {
        final record = await _runner.runIfDue();
        await _refreshState();
        return record;
      } catch (e) {
        // Yalnızca durum dosyası yazılamadığında buraya düşülür; zamanlayıcı durmaz.
        stderr.writeln('[BackupSchedule] Zamanlanmış yedek kontrolü başarısız: $e');
        return null;
      } finally {
        _setRunning(false);
        completer.complete();
        if (identical(_pendingTick, completer.future)) _pendingTick = null;
      }
    }();
  }

  Future<void> _refreshState() async {
    final schedule = await stateStore.load();
    if (mounted) state = state.copyWith(scheduleState: schedule);
  }

  void _setRunning(bool value) {
    if (mounted) state = state.copyWith(isRunning: value);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
