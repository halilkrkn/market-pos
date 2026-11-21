import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
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
            message: 'Google Drive yedeği yapılandırılmadı: Owner\'ın Google Cloud OAuth istemci kimliği '
                'oluşturması gerekir (yalnızca drive.file izni). Yerel ve USB yedekleme çalışmaya devam eder.',
          )
        else
          FutureBuilder<bool>(
            future: drive.isConnected(),
            builder: (context, snap) {
              final connected = snap.data ?? false;
              return Wrap(spacing: MmsSpacing.sm, runSpacing: MmsSpacing.sm, children: [
                AppBadge(
                  label: connected ? 'Google Drive bağlı' : 'Google Drive bağlı değil',
                  tone: connected ? AppBadgeTone.success : AppBadgeTone.warning,
                  compact: true,
                ),
                if (isDesktop)
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const Key('gdrive_connect_button'),
                      onPressed: _busy
                          ? null
                          : () => _guard(() async {
                                if (connected) {
                                  await drive.disconnect();
                                  return 'Google Drive bağlantısı kaldırıldı.';
                                }
                                await drive.connect();
                                return 'Google Drive bağlandı. Otomatik yedekler şifreli olarak yüklenecek.';
                              }).then((_) => setState(() {})),
                      child: Text(connected ? 'Bağlantıyı Kaldır' : 'Google Drive\'ı Bağla'),
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
}
