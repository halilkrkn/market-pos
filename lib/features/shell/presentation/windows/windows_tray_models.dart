import 'package:flutter/foundation.dart';

import '../../../backup/application/backup_schedule_controller.dart';
import '../../../diagnostics/domain/system_status.dart';
import '../../../sync/domain/hub_connection_state.dart';
import '../../../sync/domain/sync_coordinator_state.dart';

/// Windows Sistem Tepsisi sağ tık menüsü ve çift tık eylemleri.
enum WindowsTrayMenuAction {
  openApp('openApp'),
  openHubStatus('openHubStatus'),
  openSyncStatus('openSyncStatus'),
  openBackupStatus('openBackupStatus'),
  openSettings('openSettings'),
  requestExit('requestExit');

  final String wireName;
  const WindowsTrayMenuAction(this.wireName);

  static WindowsTrayMenuAction? fromWireName(String? raw) {
    if (raw == null) return null;
    for (final action in values) {
      if (action.wireName == raw) return action;
    }
    return null;
  }
}

/// Sistem tepsisi menüsünde ve ipucu metninde (tooltip) gösterilen gerçek durum özeti.
@immutable
class WindowsTrayStatusSnapshot {
  final String hubStatusLabel;
  final String syncStatusLabel;
  final String backupStatusLabel;
  final String tooltip;

  const WindowsTrayStatusSnapshot({
    required this.hubStatusLabel,
    required this.syncStatusLabel,
    required this.backupStatusLabel,
    required this.tooltip,
  });

  static const initial = WindowsTrayStatusSnapshot(
    hubStatusLabel: 'Hub Durumu: Kontrol ediliyor',
    syncStatusLabel: 'Senkronizasyon Durumu: Hazır',
    backupStatusLabel: 'Yedekleme Durumu: Kapalı',
    tooltip: 'MARKET MMS',
  );

  Map<String, String> toChannelMap() => {
        'hubStatus': hubStatusLabel,
        'syncStatus': syncStatusLabel,
        'backupStatus': backupStatusLabel,
        'tooltip': tooltip,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is WindowsTrayStatusSnapshot &&
            other.hubStatusLabel == hubStatusLabel &&
            other.syncStatusLabel == syncStatusLabel &&
            other.backupStatusLabel == backupStatusLabel &&
            other.tooltip == tooltip);
  }

  @override
  int get hashCode => Object.hash(
        hubStatusLabel,
        syncStatusLabel,
        backupStatusLabel,
        tooltip,
      );
}

/// Uygulamanın gerçek durum modellerini tepsi metinlerine dönüştürür (sahte başarı üretmez).
class WindowsTrayStatusFormatter {
  const WindowsTrayStatusFormatter._();

  static WindowsTrayStatusSnapshot format({
    required SystemStatus systemStatus,
    required HubConnectionState hubConnection,
    required SyncCoordinatorState syncState,
    required BackupScheduleViewState backupState,
  }) {
    final String hubShort;
    switch (systemStatus.backendState) {
      case BackendConnectionState.online:
        hubShort = 'Çevrimiçi';
      case BackendConnectionState.checking:
        hubShort = hubConnection.phase == HubConnectionPhase.discovering
            ? 'Hub Aranıyor'
            : 'Kontrol Ediliyor';
      case BackendConnectionState.draining:
        hubShort = 'Bakım / Kapanıyor';
      case BackendConnectionState.tlsPinMismatch:
        hubShort = 'TLS Pin Hatası';
      case BackendConnectionState.tlsCertError:
        hubShort = 'Sertifika Hatası';
      case BackendConnectionState.offline:
        hubShort = hubConnection.hasActiveHubUrl
            ? 'Çevrimdışı'
            : 'Yapılandırılmadı';
    }

    final pending = systemStatus.outboxSummary.totalUnsynced;
    final String syncShort;
    if (syncState.isSyncing || syncState.status == SyncCoordinatorStatus.syncing) {
      syncShort = 'Senkronize Ediliyor';
    } else if (syncState.status == SyncCoordinatorStatus.tlsPinMismatch) {
      syncShort = 'TLS Pin Hatası';
    } else if (syncState.status == SyncCoordinatorStatus.tlsCertError) {
      syncShort = 'Sertifika Hatası';
    } else if (syncState.status == SyncCoordinatorStatus.authRequired) {
      syncShort = 'Yetki Gerekli';
    } else if (syncState.status == SyncCoordinatorStatus.permanentError) {
      syncShort = 'Kalıcı Hata (${systemStatus.outboxSummary.failedPermanent})';
    } else if (syncState.status == SyncCoordinatorStatus.paused) {
      syncShort = 'Duraklatıldı';
    } else if (pending > 0) {
      syncShort = 'Bekleyen ($pending)';
    } else if (syncState.status == SyncCoordinatorStatus.networkError) {
      syncShort = 'Bağlantı Bekliyor';
    } else if (syncState.status == SyncCoordinatorStatus.error) {
      syncShort = 'Hata';
    } else {
      syncShort = 'Güncel';
    }

    final String backupShort;
    if (backupState.isRunning) {
      backupShort = 'Yedek Alınıyor';
    } else if (!backupState.settings.enabled) {
      backupShort = 'Otomatik Yedek Kapalı';
    } else if (backupState.isOverdue) {
      backupShort = 'Gecikmiş (${backupState.settings.intervalHours}s)';
    } else {
      backupShort = 'Aktif (${backupState.settings.intervalHours}s)';
    }

    return WindowsTrayStatusSnapshot(
      hubStatusLabel: 'Hub Durumu: $hubShort',
      syncStatusLabel: 'Senkronizasyon Durumu: $syncShort',
      backupStatusLabel: 'Yedekleme Durumu: $backupShort',
      tooltip: 'MARKET MMS — Hub: $hubShort | Senkron: $syncShort',
    );
  }
}

const Object _trayUnset = Object();

/// Windows Sistem Tepsisi ve Otomatik Başlatma arayüz durumu.
@immutable
class WindowsTrayState {
  final bool isSupported;
  final bool isTrayActive;
  final bool autoStartEnabled;
  final bool isAutoStartBusy;
  final bool isExiting;
  final String? lastError;

  const WindowsTrayState({
    required this.isSupported,
    required this.isTrayActive,
    required this.autoStartEnabled,
    this.isAutoStartBusy = false,
    this.isExiting = false,
    this.lastError,
  });

  const WindowsTrayState.initial({this.isSupported = false})
      : isTrayActive = false,
        autoStartEnabled = false,
        isAutoStartBusy = false,
        isExiting = false,
        lastError = null;

  WindowsTrayState copyWith({
    bool? isSupported,
    bool? isTrayActive,
    bool? autoStartEnabled,
    bool? isAutoStartBusy,
    bool? isExiting,
    Object? lastError = _trayUnset,
  }) {
    return WindowsTrayState(
      isSupported: isSupported ?? this.isSupported,
      isTrayActive: isTrayActive ?? this.isTrayActive,
      autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
      isAutoStartBusy: isAutoStartBusy ?? this.isAutoStartBusy,
      isExiting: isExiting ?? this.isExiting,
      lastError: identical(lastError, _trayUnset)
          ? this.lastError
          : lastError as String?,
    );
  }
}
