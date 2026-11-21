import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../application/client_backup_service.dart';
import '../../backup_providers.dart';

/// Faz 7D — USB / ağ klasörü aktarımı ve Google Drive bağlantısı.
class ExternalBackupSection extends ConsumerStatefulWidget {
  const ExternalBackupSection({super.key});

  @override
  ConsumerState<ExternalBackupSection> createState() => _ExternalBackupSectionState();
}

class _ExternalBackupSectionState extends ConsumerState<ExternalBackupSection> {
  final _usbDirController = TextEditingController();
  final _importFileController = TextEditingController();
  String? _message;
  AppBadgeTone _tone = AppBadgeTone.info;
  bool _busy = false;

  @override
  void dispose() {
    _usbDirController.dispose();
    _importFileController.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await action();
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.success;
        _message = ok;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.danger;
        _message = switch (e) {
          BackupException(:final message) => message,
          DriveBackupException(:final message) => message,
          _ => UserFriendlyErrorMapper.map(e),
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final isDesktop = ref.watch(mmsUiProfileProvider).isDesktop;
    final drive = ref.watch(googleDriveConnectServiceProvider);
    final service = ref.read(clientBackupServiceProvider);

    return Column(
      key: const Key('external_backup_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Harici Yedek (USB / Google Drive)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        const SizedBox(height: MmsSpacing.xs),
        if (isDesktop) ...[
          TextField(
            key: const Key('usb_target_dir_field'),
            controller: _usbDirController,
            decoration: const InputDecoration(
              labelText: 'USB / klasör yolu (ör. E:\\MMS_Yedek)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.xs),
          Wrap(spacing: MmsSpacing.sm, runSpacing: MmsSpacing.sm, children: [
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const Key('usb_export_button'),
                onPressed: _busy
                    ? null
                    : () => _guard(() async {
                          final out = await service.exportLatestBackupTo(Directory(_usbDirController.text.trim()));
                          return 'Son yedek doğrulanarak kopyalandı: ${out.path}';
                        }),
                icon: const Icon(Icons.usb_rounded),
                label: const Text('Son Yedeği Aktar'),
              ),
            ),
          ]),
          const SizedBox(height: MmsSpacing.sm),
          TextField(
            key: const Key('usb_import_file_field'),
            controller: _importFileController,
            decoration: const InputDecoration(
              labelText: 'İçe aktarılacak .mmsbak dosyası',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.xs),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const Key('usb_import_button'),
              onPressed: _busy
                  ? null
                  : () => _guard(() async {
                        final info = await service.importBackupFile(File(_importFileController.text.trim()));
                        ref.invalidate(backupListProvider);
                        return 'Yedek içe aktarıldı (${info.backupId.substring(0, 8)}...). Listeden geri yükleyebilirsiniz.';
                      }),
              icon: const Icon(Icons.download_rounded),
              label: const Text('USB\'den İçe Aktar'),
            ),
          ),
        ] else
          Text(
            'USB aktarımı Windows uygulamasından yapılır. Android cihazlarda harici yedek için Google Drive kullanılır.',
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
          ),
        const SizedBox(height: MmsSpacing.md),
        if (!drive.isConfigured)
          const DiagnosticsInlineBanner(
            key: Key('gdrive_not_configured_banner'),
            tone: AppBadgeTone.warning,
            message: 'Google Drive yedeği yapılandırılmadı: Owner\'ın platforma uygun Google Cloud OAuth '
                'istemci kimliğini tanımlaması gerekir (yalnızca drive.file izni). Yerel yedekleme çalışmaya devam eder.',
          )
        else
          FutureBuilder<bool>(
            future: drive.isConnected(),
            builder: (context, snap) {
              final connected = snap.data ?? false;
              final uploader = ref.watch(googleDriveUploaderProvider);
              final backupService = ref.watch(clientBackupServiceProvider);
              return Wrap(spacing: MmsSpacing.sm, runSpacing: MmsSpacing.sm, children: [
                AppBadge(
                  label: connected ? 'Google Drive bağlı' : 'Google Drive bağlı değil',
                  tone: connected ? AppBadgeTone.success : AppBadgeTone.warning,
                  compact: true,
                ),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: const Key('gdrive_connect_button'),
                    onPressed: _busy
                        ? null
                        : () => _guard(() async {
                              if (connected) {
                                await drive.disconnect(tokenProvider: uploader?.tokenProvider);
                                return 'Google Drive bağlantısı kaldırıldı.';
                              }
                              await drive.connect();
                              return 'Google Drive bağlandı. Otomatik yedekler şifreli olarak yüklenecek.';
                            }).then((_) {
                              if (mounted) setState(() {});
                            }),
                    child: Text(connected ? 'Bağlantıyı Kaldır' : 'Google Drive\'ı Bağla'),
                  ),
                ),
                if (connected && uploader != null)
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      key: const Key('gdrive_list_backups_button'),
                      onPressed: _busy
                          ? null
                          : () => _openDriveRestoreDialog(
                                context: context,
                                uploader: uploader,
                                backupService: backupService,
                              ),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Drive Yedeklerinden Geri Yükle'),
                    ),
                  ),
              ]);
            },
          ),
        if (_message != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(key: const Key('external_backup_status_banner'), tone: _tone, message: _message!),
        ],
      ],
    );
  }

  Future<void> _openDriveRestoreDialog({
    required BuildContext context,
    required GoogleDriveBackupUploader uploader,
    required ClientBackupService backupService,
  }) async {
    await _guard(() async {
      final remoteBackups = await backupService.listGoogleDriveBackups(uploader: uploader);
      if (!context.mounted) return 'İşlem iptal edildi.';
      if (remoteBackups.isEmpty) {
        return 'Google Drive üzerinde geri yüklenebilecek şifreli yedek bulunamadı.';
      }

      DriveRemoteBackupInfo selected = remoteBackups.first;
      final passwordController = TextEditingController();
      String? dialogError;
      bool restoring = false;

      final restored = await showDialog<RestoreResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Google Drive Yedeklerinden Geri Yükle'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Geri yükleme öncesinde indirilen .mmsbak paketinin bütünlüğü, '
                    'cihaz/şube kimliği ve parolası doğrulanır; canlı veritabanı '
                    'koruyucu kopya alınmadan değiştirilmez ve bekleyen Outbox korunur.',
                  ),
                  const SizedBox(height: MmsSpacing.sm),
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: remoteBackups.length,
                      itemBuilder: (_, index) {
                        final item = remoteBackups[index];
                        final isSelected = item.fileId == selected.fileId;
                        final ts = item.createdTimeUtc?.toLocal().toString().substring(0, 16) ?? '-';
                        final kb = (item.sizeBytes / 1024).toStringAsFixed(1);
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          leading: Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          ),
                          title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$ts · $kb KB'),
                          onTap: restoring ? null : () => setDialogState(() => selected = item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: MmsSpacing.sm),
                  TextField(
                    key: const Key('gdrive_restore_password_field'),
                    controller: passwordController,
                    obscureText: true,
                    enabled: !restoring,
                    decoration: const InputDecoration(
                      labelText: 'Yedekleme parolası',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: MmsSpacing.xs),
                    Text(
                      dialogError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: restoring ? null : () => Navigator.of(dialogCtx).pop(null),
                  child: const Text('İptal'),
                ),
              ),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const Key('gdrive_restore_confirm_button'),
                  onPressed: restoring
                      ? null
                      : () async {
                          final pw = passwordController.text;
                          if (pw.trim().isEmpty) {
                            setDialogState(() => dialogError = 'Yedek parolasını girin.');
                            return;
                          }
                          setDialogState(() {
                            restoring = true;
                            dialogError = null;
                          });
                          try {
                            final result = await backupService.downloadAndRestoreFromGoogleDrive(
                              uploader: uploader,
                              remote: selected,
                              password: pw,
                            );
                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(result);
                          } catch (e) {
                            setDialogState(() {
                              restoring = false;
                              dialogError = switch (e) {
                                BackupException(:final message) => message,
                                DriveBackupException(:final message) => message,
                                _ => UserFriendlyErrorMapper.map(e),
                              };
                            });
                          }
                        },
                  child: Text(restoring ? 'Doğrulanıyor...' : 'Geri Yüklemeyi Başlat'),
                ),
              ),
            ],
          ),
        ),
      );
      passwordController.dispose();
      if (restored == null) {
        return 'Google Drive geri yüklemesi iptal edildi.';
      }
      ref.invalidate(backupListProvider);
      return 'Google Drive yedeği (${restored.backupId.substring(0, 8)}...) başarıyla geri yüklendi.';
    });
  }
}
