import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../backup_providers.dart';
import 'backup_schedule_section.dart';
import 'external_backup_section.dart';

/// S5A-4 AES-256-CBC + HMAC-SHA256 + PBKDF2-600k Şifreli Yerel Yedekleme Kartı.
class BackupManagementCard extends ConsumerStatefulWidget {
  const BackupManagementCard({super.key});

  @override
  ConsumerState<BackupManagementCard> createState() =>
      _BackupManagementCardState();
}

class _BackupManagementCardState extends ConsumerState<BackupManagementCard> {
  final _passwordController = TextEditingController();
  bool _isBusy = false;
  String? _statusMessage;
  AppBadgeTone _statusTone = AppBadgeTone.info;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createBackup() async {
    final password = _passwordController.text;
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    try {
      final result = await ref
          .read(clientBackupServiceProvider)
          .createEncryptedBackup(password: password);
      ref.invalidate(backupListProvider);
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Şifreli yedek oluşturuldu (${result.backupId.substring(0, 8)}..., ${(result.encryptedSizeBytes / 1024).toStringAsFixed(1)} KB).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e is BackupException
            ? e.message
            : UserFriendlyErrorMapper.map(
                e,
                fallback: 'Yedek oluşturulurken hata oluştu.',
              );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _restoreBackup(BackupPackageInfo info) async {
    final password = await _promptRestorePassword(context, info.backupId);
    if (password == null || !mounted) return;

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    try {
      final result = await ref
          .read(clientBackupServiceProvider)
          .restoreEncryptedBackup(
            backupId: info.backupId,
            password: password,
          );
      if (!mounted) return;
      invalidatePostRestoreProviders(ref);
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Yedek başarıyla geri yüklendi (${result.backupId.substring(0, 8)}...). Koruyucu güvenlik yedeği alındı.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e is BackupException
            ? e.message
            : UserFriendlyErrorMapper.map(
                e,
                fallback: 'Yedek geri yüklenemedi.',
              );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<String?> _promptRestorePassword(
    BuildContext context,
    String backupId,
  ) {
    final controller = TextEditingController(text: _passwordController.text);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Yedekten Geri Yükle',
        icon: Icons.restore_rounded,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Seçilen yedek ($backupId) çözülüp bütünlüğü doğrulandıktan sonra canlı veritabanının yerine alınır. İşlem öncesi otomatik güvenlik yedeği alınır.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: MmsSpacing.md),
            TextField(
              key: const Key('restore_password_dialog_field'),
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yedekleme Parolası',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
          ),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('restore_confirm_dialog_button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Doğrula ve Geri Yükle'),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final backupsAsync = ref.watch(backupListProvider);

    return DiagnosticsSectionCard(
      key: const Key('diagnostics_backup_card'),
      title: 'Legacy Yerel Cihaz Yedeği (S5A-4)',
      subtitle: 'Yerel SQLite dosyası için AES-256-CBC · PBKDF2-HMAC-SHA256',
      trailing: const AppBadge(
        label: 'AES-256 + HMAC',
        tone: AppBadgeTone.info,
        icon: Icons.enhanced_encryption_rounded,
        compact: true,
      ),
      children: [
        TextField(
          key: const Key('backup_password_field'),
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Yedek Parolası (en az 8 karakter)',
            hintText: 'Parola loglanmaz veya düz metin saklanmaz',
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
              child: FilledButton.icon(
                key: const Key('create_backup_button'),
                onPressed: _isBusy ? null : _createBackup,
                icon: _isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_rounded),
                label: Text(_isBusy ? 'İşleniyor...' : 'Şifreli Yedek Al'),
              ),
            ),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const Key('refresh_backups_button'),
                onPressed: _isBusy
                    ? null
                    : () => ref.invalidate(backupListProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yedekleri Yenile'),
              ),
            ),
          ],
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('backup_status_banner'),
            tone: _statusTone,
            message: _statusMessage!,
          ),
        ],
        const SizedBox(height: MmsSpacing.md),
        backupsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: MmsSpacing.sm),
            child: LinearProgressIndicator(),
          ),
          error: (err, _) => DiagnosticsInlineBanner(
            tone: AppBadgeTone.danger,
            message: UserFriendlyErrorMapper.map(
              err,
              fallback: 'Yedek listesi okunamadı.',
            ),
          ),
          data: (backups) {
            if (backups.isEmpty) {
              return Text(
                'Henüz alınmış yerel şifreli yedek bulunmuyor.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in backups.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: MmsSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.archive_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: MmsSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.backupId.substring(0, 12)} · ${(item.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                '${item.timestamp.toLocal()} · şema v${item.manifest.schemaVersion}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            key: Key('restore_backup_button_${item.backupId}'),
                            onPressed:
                                _isBusy ? null : () => _restoreBackup(item),
                            child: const Text('Geri Yükle'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const Divider(height: MmsSpacing.xl),
        const BackupScheduleSection(),
        const Divider(height: MmsSpacing.xl),
        const ExternalBackupSection(),
      ],
    );
  }
}
