import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../backup_providers.dart';
import '../../data/hub_backup_client.dart';

/// Google Drive Yedekleme ve Kurtarma Kartı (Tek Kullanıcı / Market Sahibi Modu).
class HubCentralBackupCard extends ConsumerStatefulWidget {
  const HubCentralBackupCard({super.key});

  @override
  ConsumerState<HubCentralBackupCard> createState() =>
      _HubCentralBackupCardState();
}

class _HubCentralBackupCardState extends ConsumerState<HubCentralBackupCard> {
  final _recoveryKeyController = TextEditingController();
  final _restoreBackupIdController = TextEditingController();
  final _restorePasswordController = TextEditingController();

  bool _isBusy = false;
  HubCentralBackupOverview? _overview;
  List<HubDriveRemoteBackup> _driveBackups = const [];
  String? _selectedDriveFileId;
  String? _selectedDriveBackupId;
  String? _statusMessage;
  AppBadgeTone _statusTone = AppBadgeTone.info;

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    _restoreBackupIdController.dispose();
    _restorePasswordController.dispose();
    super.dispose();
  }

  String _friendlyJobStateLabel(HubBackupJobState state) {
    switch (state) {
      case HubBackupJobState.completedUploaded:
        return 'Yedeklendi';
      case HubBackupJobState.retryPending:
        return 'Tekrar Denenecek';
      case HubBackupJobState.failedAuth:
        return 'Google Oturumu Gerekli';
      case HubBackupJobState.failedQuota:
        return 'Drive Alanı Dolu';
      case HubBackupJobState.uploading:
      case HubBackupJobState.verifying:
        return 'Yükleniyor';
      case HubBackupJobState.superseded:
        return 'Yenilendi';
      default:
        return 'Hazırlanıyor';
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      await action();
    } on HubBackupClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403 || e.isOwnerRoleRequired) {
        ref
            .read(deviceRoleProvider.notifier)
            .invalidateFromAuthError(code: e.code);
      }
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e.isOwnerRoleRequired
            ? 'Bu işlem yalnızca ana bilgisayar yetkisiyle yapılabilir.'
            : e.message;
      });
    } on DriveBackupException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = UserFriendlyErrorMapper.map(
          e,
          fallback: 'Google Drive yedekleme işlemi tamamlanamadı.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _refreshStatus() async {
    await _runBusy(() async {
      await ref.read(deviceRoleProvider.notifier).refreshRole(force: true);
      final currentRole = ref
          .read(hubBackupDeviceRoleProvider)
          .trim()
          .toUpperCase();
      if (currentRole != 'OWNER') {
        if (!mounted) return;
        setState(() {
          _overview = null;
          _statusTone = AppBadgeTone.warning;
          _statusMessage = 'Bu bilgisayarda yetki doğrulanamadı. İlk kurulumu tamamlayın veya bağlantıyı yenileyin.';
        });
        return;
      }
      final overview = await ref.read(hubBackupClientProvider).fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = AppBadgeTone.info;
        _statusMessage = 'Yedekleme durumu güncellendi.';
      });
    });
  }

  Future<void> _connectHubDrive() async {
    await _runBusy(() async {
      final handoff = ref.read(hubBackupOAuthHandoffServiceProvider);
      final res = await handoff.connectViaWindowsBrowser();
      final overview = await ref.read(hubBackupClientProvider).fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Google Drive bağlantısı tamamlandı (${res.accountEmail ?? 'Bağlı'}).';
      });
    });
  }

  Future<void> _disconnectHubDrive() async {
    await _runBusy(() async {
      final client = ref.read(hubBackupClientProvider);
      await client.disconnectOAuth();
      final overview = await client.fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = AppBadgeTone.info;
        _statusMessage = 'Google Drive bağlantısı kesildi.';
      });
    });
  }

  Future<void> _saveRecoveryKey() async {
    await _runBusy(() async {
      final pass = _recoveryKeyController.text;
      if (pass.length < MmsbakV2Crypto.minPasswordLength) {
        throw const DriveBackupException(
          'ERR_WEAK_RECOVERY_PASSWORD',
          'Kurtarma parolası en az 12 karakter olmalıdır.',
        );
      }
      final client = ref.read(hubBackupClientProvider);
      await client.setRecoveryKey(pass);
      _recoveryKeyController.clear();
      final overview = await client.fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = AppBadgeTone.success;
        _statusMessage = 'Kurtarma parolası güvenli kasaya kaydedildi.';
      });
    });
  }

  Future<void> _toggleSchedule(bool enable) async {
    await _runBusy(() async {
      final client = ref.read(hubBackupClientProvider);
      await client.configureSchedule(
        enabled: enable,
        dailyHourLocal: 0,
        dailyMinuteLocal: 0,
        uploadToDrive: true,
      );
      final overview = await client.fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = AppBadgeTone.success;
        _statusMessage = enable
            ? 'Her gece 00:00 otomatik Google Drive yedeklemesi açıldı.'
            : 'Otomatik Google Drive yedeklemesi kapatıldı.';
      });
    });
  }

  Future<void> _triggerManualBackup() async {
    await _runBusy(() async {
      if (_recoveryKeyController.text.isNotEmpty) {
        throw const DriveBackupException(
          'ERR_UNSAVED_RECOVERY_PASSWORD',
          'Kurtarma parolası alanında kaydedilmemiş metin var. Önce "Parolayı Kaydet" '
              'ile kaydedin veya alanı temizleyin; yedek yalnızca kayıtlı parolayla şifrelenir.',
        );
      }
      final known = _overview;
      if (known != null && !known.hasRecoveryKey) {
        throw const DriveBackupException(
          'ERR_RECOVERY_KEY_REQUIRED',
          'Henüz kayıtlı kurtarma parolası yok. Önce en az 12 karakterli parolayı '
              'kaydedin; yedek bu kayıtlı parolayla şifrelenir.',
        );
      }
      final client = ref.read(hubBackupClientProvider);
      final job = await client.triggerManualBackup();
      final overview = await client.fetchStatus();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _statusTone = job.state == HubBackupJobState.completedUploaded
            ? AppBadgeTone.success
            : AppBadgeTone.warning;
        _statusMessage =
            'Yedekleme sonucu: ${_friendlyJobStateLabel(job.state)} · kayıtlı kurtarma parolasıyla şifrelendi.';
      });
    });
  }

  Future<void> _listDriveBackups() async {
    await _runBusy(() async {
      final list = await ref.read(hubBackupClientProvider).fetchDriveBackups();
      if (!mounted) return;
      setState(() {
        _driveBackups = list;
        _statusTone = AppBadgeTone.info;
        _statusMessage = list.isEmpty
            ? 'Google Drive klasöründe kayıtlı yedek bulunamadı.'
            : '${list.length} Google Drive yedeği listelendi.';
      });
    });
  }

  void _selectDriveBackup(HubDriveRemoteBackup item) {
    setState(() {
      _selectedDriveFileId = item.driveFileId;
      _selectedDriveBackupId = item.backupId;
      _restoreBackupIdController.text = item.backupId ?? '';
    });
  }

  Future<void> _restoreFromHubBackup() async {
    await _runBusy(() async {
      final pass = _restorePasswordController.text;
      if (pass.isEmpty) {
        throw const DriveBackupException(
          'ERR_RECOVERY_PASSWORD_REQUIRED',
          'Geri yükleme için kurtarma parolasını girin.',
        );
      }
      final backupId = _restoreBackupIdController.text.trim();
      final driveFileId =
          (_selectedDriveBackupId == null || _selectedDriveBackupId == backupId)
          ? _selectedDriveFileId
          : null;
      final res = await ref
          .read(hubBackupClientProvider)
          .restoreFromBackup(
            backupId: backupId.isEmpty ? null : backupId,
            driveFileId: driveFileId,
            recoveryPassword: pass,
          );
      _restorePasswordController.clear();
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Veritabanı geri yüklendi (${res['restore_epoch']}). Cihazlar yeniden doğrulamaya geçirildi.';
      });
    });
  }

  AppBadge _buildJobBadge(HubCentralBackupOverview? overview) {
    final latest = overview?.latestJob;
    if (latest == null) {
      return const AppBadge(
        label: 'Hazır',
        tone: AppBadgeTone.info,
        icon: Icons.cloud_queue_rounded,
        compact: true,
      );
    }
    final label = _friendlyJobStateLabel(latest.state);
    switch (latest.state) {
      case HubBackupJobState.completedUploaded:
        return AppBadge(
          label: label,
          tone: AppBadgeTone.success,
          icon: Icons.cloud_done_rounded,
          compact: true,
        );
      case HubBackupJobState.failedAuth:
      case HubBackupJobState.failedQuota:
        return AppBadge(
          label: label,
          tone: AppBadgeTone.danger,
          icon: Icons.cloud_off_rounded,
          compact: true,
        );
      case HubBackupJobState.retryPending:
        return AppBadge(
          label: label,
          tone: AppBadgeTone.warning,
          icon: Icons.schedule_rounded,
          compact: true,
        );
      default:
        return AppBadge(
          label: label,
          tone: AppBadgeTone.info,
          icon: Icons.sync_rounded,
          compact: true,
        );
    }
  }

  String _formatSchedulerError(HubSchedulerLastError err) {
    switch (err.code) {
      case 'ERR_RECOVERY_KEY_NOT_CONFIGURED':
      case 'ERR_RECOVERY_KEY_REQUIRED':
        return 'Otomatik yedekleme bekliyor: Kurtarma parolası henüz tanımlanmamış.';
      case 'ERR_RECOVERY_KEY_CORRUPTED':
        return 'Otomatik yedekleme hatası: Kurtarma parolası okunamadı; parolayı yeniden kaydedin.';
      case 'ERR_INSUFFICIENT_DISK_SPACE':
        return 'Otomatik yedekleme duraklatıldı: Diskte yeterli boş alan yok.';
      default:
        final msg = UserFriendlyErrorMapper.map(
          err.message.isNotEmpty ? err.message : err.code,
          fallback:
              'Otomatik yedekleme zamanlayıcısında geçici bir hata oluştu.',
        );
        return 'Zamanlayıcı uyarısı: $msg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final role = ref.watch(hubBackupDeviceRoleProvider).toUpperCase();
    final isDesktop = uiProfile.isDesktop;
    final isOwner = role == 'OWNER';
    final overview = _overview;

    if (!isDesktop && !isOwner) {
      return const DiagnosticsSectionCard(
        key: Key('hub_central_backup_card'),
        title: 'Google Drive Yedekleme',
        subtitle: 'Yedekleme ayarları ana bilgisayardan yönetilir.',
        trailing: AppBadge(
          label: 'Yalnızca Bilgisayardan',
          tone: AppBadgeTone.warning,
          icon: Icons.lock_outline_rounded,
          compact: true,
        ),
        children: [
          DiagnosticsInlineBanner(
            key: Key('hub_backup_cashier_restricted'),
            tone: AppBadgeTone.warning,
            message: 'Google Drive yedekleme yönetimi yalnızca ana bilgisayardan yapılabilir.',
          ),
        ],
      );
    }

    final hubConn = ref.watch(hubConnectionProvider);
    final isDriveConnected = overview?.oauthConnected ?? false;

    return DiagnosticsSectionCard(
      key: const Key('hub_central_backup_card'),
      title: 'Google Drive Yedekleme',
      subtitle: isDesktop
          ? 'Her gece 00:00 otomatik şifreli yedekleme · En güncel 2 yedek saklanır'
          : 'Ana bilgisayar üzerinden Google Drive yedekleme durumu',
      trailing: _buildJobBadge(overview),
      children: [
        DiagnosticsKeyValueRow(
          label: 'Ana Bilgisayar',
          value: hubConn.activeHubUrl != null
              ? 'Hazır (${Uri.tryParse(hubConn.activeHubUrl!)?.host ?? 'Yerel'})'
              : 'Henüz bağlanmadı',
        ),
        if (overview != null) ...[
          DiagnosticsKeyValueRow(
            label: 'Google Drive',
            value: overview.oauthConnected
                ? 'Bağlı (${overview.accountEmail ?? 'Google Hesabı'})'
                : (overview.needsReauth
                      ? 'Yeniden Giriş Gerekli'
                      : 'Bağlı Değil'),
          ),
          DiagnosticsKeyValueRow(
            label: 'Kurtarma Parolası',
            value: overview.hasRecoveryKey ? 'Kayıtlı' : 'Belirlenmedi',
          ),
          DiagnosticsKeyValueRow(
            label: 'Gece 00:00 Otomatik Yedek',
            value: overview.schedule.enabled ? 'Açık' : 'Kapalı',
          ),
          if (overview.latestJob != null)
            DiagnosticsKeyValueRow(
              label: 'Son Yedek Durumu',
              value: _friendlyJobStateLabel(overview.latestJob!.state),
            ),
          if (overview.schedulerLastError != null) ...[
            const SizedBox(height: MmsSpacing.xs),
            DiagnosticsInlineBanner(
              key: const Key('hub_scheduler_last_error_banner'),
              tone: AppBadgeTone.warning,
              message: _formatSchedulerError(overview.schedulerLastError!),
            ),
          ],
        ],
        const SizedBox(height: MmsSpacing.sm),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            if (isDesktop && isOwner && !isDriveConnected)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('hub_oauth_connect_button'),
                  onPressed: _isBusy ? null : _connectHubDrive,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text("Google Drive'a Bağlan"),
                ),
              ),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const Key('hub_backup_refresh_button'),
                onPressed: _isBusy ? null : _refreshStatus,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Durumu Yenile'),
              ),
            ),
            if (isOwner)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('hub_manual_backup_button'),
                  onPressed: _isBusy ? null : _triggerManualBackup,
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Şimdi Yedekle'),
                ),
              ),
            if (isDesktop && isOwner && isDriveConnected)
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('hub_oauth_disconnect_button'),
                  onPressed: _isBusy ? null : _disconnectHubDrive,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Drive Bağlantısını Kes'),
                ),
              ),
          ],
        ),
        if (isDesktop && !isOwner) ...[
          const SizedBox(height: MmsSpacing.sm),
          const DiagnosticsInlineBanner(
            key: Key('hub_backup_owner_required_banner'),
            tone: AppBadgeTone.warning,
            message: 'Google Drive yedekleme ve geri yükleme için ana bilgisayar kurulumunun tamamlanmış olması gerekir. "Durumu Yenile" ile kontrol edebilirsiniz.',
          ),
        ],
        if (isDesktop && isOwner) ...[
          const SizedBox(height: MmsSpacing.md),
          TextField(
            key: const Key('hub_recovery_key_field'),
            controller: _recoveryKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Kurtarma Parolası (en az 12 karakter)',
              hintText: 'Yeni bilgisayarda geri yükleme için gereklidir',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
          Wrap(
            spacing: MmsSpacing.sm,
            runSpacing: MmsSpacing.sm,
            children: [
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('hub_save_recovery_key_button'),
                  onPressed: _isBusy ? null : _saveRecoveryKey,
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Parolayı Kaydet'),
                ),
              ),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('hub_schedule_toggle_button'),
                  onPressed: _isBusy
                      ? null
                      : () => _toggleSchedule(
                          !(overview?.schedule.enabled ?? false),
                        ),
                  icon: const Icon(Icons.event_repeat_rounded),
                  label: Text(
                    (overview?.schedule.enabled ?? false)
                        ? 'Gece 00:00 Yedeğini Kapat'
                        : 'Gece 00:00 Yedeğini Aç',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MmsSpacing.md),
          TextField(
            key: const Key('hub_restore_backup_id_field'),
            controller: _restoreBackupIdController,
            onChanged: (val) {
              if (_selectedDriveFileId != null &&
                  _selectedDriveBackupId != val.trim()) {
                setState(() {
                  _selectedDriveFileId = null;
                  _selectedDriveBackupId = null;
                });
              }
            },
            decoration: const InputDecoration(
              labelText: 'Geri Yüklenecek Yedek ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
          TextField(
            key: const Key('hub_restore_password_field'),
            controller: _restorePasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Geri Yükleme Parolası (12+ karakter)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
          Wrap(
            spacing: MmsSpacing.sm,
            runSpacing: MmsSpacing.sm,
            children: [
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('hub_drive_list_backups_button'),
                  onPressed: _isBusy ? null : _listDriveBackups,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('Drive Yedeklerini Listele'),
                ),
              ),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('hub_restore_button'),
                  onPressed: _isBusy ? null : _restoreFromHubBackup,
                  icon: const Icon(Icons.restore_page_rounded),
                  label: const Text('Yedekten Geri Yükle'),
                ),
              ),
            ],
          ),
          if (_driveBackups.isNotEmpty) ...[
            const SizedBox(height: MmsSpacing.sm),
            for (final item in _driveBackups)
              Padding(
                padding: const EdgeInsets.only(bottom: MmsSpacing.xs),
                child: InkWell(
                  key: Key('hub_drive_backup_item_${item.driveFileId}'),
                  onTap: _isBusy ? null : () => _selectDriveBackup(item),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MmsSpacing.sm,
                      vertical: MmsSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedDriveFileId == item.driveFileId
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.backupId ?? item.fileName} (${item.sizeBytes} B)',
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        AppBadge(
                          label: item.cachedLocally
                              ? 'Yerel + Drive'
                              : 'Yalnızca Drive',
                          tone: item.cachedLocally
                              ? AppBadgeTone.success
                              : AppBadgeTone.info,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('hub_central_backup_banner'),
            tone: _statusTone,
            message: _statusMessage!,
          ),
        ],
      ],
    );
  }
}
