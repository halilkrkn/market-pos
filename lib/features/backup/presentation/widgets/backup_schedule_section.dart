import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../application/backup_schedule_controller.dart';
import '../../backup_providers.dart';

/// Faz 3 — Otomatik (zamanlanmış) yerel yedekleme ayarları, durum ve geçmiş.
class BackupScheduleSection extends ConsumerStatefulWidget {
  const BackupScheduleSection({super.key});

  @override
  ConsumerState<BackupScheduleSection> createState() => _BackupScheduleSectionState();
}

class _BackupScheduleSectionState extends ConsumerState<BackupScheduleSection> {
  final _passwordController = TextEditingController();
  int _intervalHours = 24;
  String? _message;
  AppBadgeTone _tone = AppBadgeTone.info;
  bool _busy = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action, String successMessage) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.success;
        _message = successMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.danger;
        _message = e is BackupException ? e.message : UserFriendlyErrorMapper.map(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime? t) => t == null ? '—' : t.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final view = ref.watch(backupScheduleControllerProvider);
    final controller = ref.read(backupScheduleControllerProvider.notifier);
    final s = view.scheduleState;

    return Column(
      key: const Key('backup_schedule_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Otomatik Yedekleme',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary),
        ),
        const SizedBox(height: MmsSpacing.xs),
        DiagnosticsKeyValueRow(
          label: 'Durum',
          value: view.settings.enabled ? 'AÇIK · her ${view.settings.intervalHours} saatte bir' : 'KAPALI',
        ),
        DiagnosticsKeyValueRow(label: 'Son başarılı yedek', value: _fmt(s.lastSuccessAt)),
        if (view.backgroundStatus.supportedOnPlatform) ...[
          DiagnosticsKeyValueRow(
            key: const Key('backup_bg_schedule_status_row'),
            label: 'Arka Plan Zamanlayıcı (Uygulama Kapalıyken)',
            value: view.backgroundStatus.isScheduled
                ? 'ZAMANLANDI · ${view.backgroundStatus.intervalMinutes} dk'
                : 'ZAMANLANMADI',
          ),
          if (view.backgroundStatus.nextRunAtUtc != null)
            DiagnosticsKeyValueRow(
              key: const Key('backup_bg_next_run_row'),
              label: 'Sonraki arka plan turu',
              value: _fmt(view.backgroundStatus.nextRunAtUtc),
            ),
          if (view.backgroundStatus.lastStatus != null)
            DiagnosticsKeyValueRow(
              key: const Key('backup_bg_last_status_row'),
              label: 'Son arka plan sonucu',
              value: view.backgroundStatus.lastErrorCode == null
                  ? '${view.backgroundStatus.lastStatus} (${_fmt(view.backgroundStatus.lastRunAtUtc)})'
                  : '${view.backgroundStatus.lastStatus} [${view.backgroundStatus.lastErrorCode}]',
            ),
        ],
        if (s.lastErrorCode != null)
          DiagnosticsInlineBanner(
            key: const Key('backup_schedule_error_banner'),
            tone: AppBadgeTone.danger,
            message: 'Son otomatik yedek başarısız (${s.consecutiveFailures} kez): ${s.lastErrorMessage ?? s.lastErrorCode}',
          )
        else if (view.isOverdue)
          const DiagnosticsInlineBanner(
            tone: AppBadgeTone.warning,
            message: 'Otomatik yedek gecikti. Uygulamanın açık olduğundan ve diskte yer olduğundan emin olun.',
          ),
        const SizedBox(height: MmsSpacing.sm),
        if (!view.settings.enabled) ...[
          TextField(
            key: const Key('backup_schedule_password_field'),
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Otomatik yedek parolası (en az 8 karakter)',
              helperText: 'Parola cihazın güvenli deposunda (DPAPI / Keystore) saklanır; geri yüklemede gereklidir.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
        ],
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!view.settings.enabled) ...[
              DropdownButton<int>(
                key: const Key('backup_schedule_interval_dropdown'),
                value: _intervalHours,
                items: [
                  for (final h in ClientBackupScheduleSettings.supportedIntervalHours)
                    DropdownMenuItem(value: h, child: Text('Her $h saatte')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _intervalHours = v ?? 24),
              ),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('backup_schedule_enable_button'),
                  onPressed: _busy
                      ? null
                      : () => _guard(() async {
                            await controller.enable(intervalHours: _intervalHours, password: _passwordController.text);
                            _passwordController.clear();
                          }, 'Otomatik yedekleme açıldı; ilk yedek alınıyor.'),
                  icon: const Icon(Icons.schedule_rounded),
                  label: const Text('Otomatik Yedeklemeyi Aç'),
                ),
              ),
            ] else ...[
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('backup_schedule_run_now_button'),
                  onPressed: _busy || view.isRunning
                      ? null
                      : () => _guard(() async {
                            final r = await controller.runNow();
                            if (r != null && !r.success) {
                              throw BackupException(r.errorCode ?? 'ERR_BACKUP_FAILED', r.errorMessage ?? 'Yedek alınamadı.');
                            }
                            ref.invalidate(backupListProvider);
                          }, 'Yedek alındı.'),
                  icon: const Icon(Icons.backup_rounded),
                  label: Text(view.isRunning ? 'Yedekleniyor...' : 'Şimdi Yedekle'),
                ),
              ),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: const Key('backup_schedule_disable_button'),
                  onPressed: _busy ? null : () => _guard(controller.disable, 'Otomatik yedekleme kapatıldı.'),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(key: const Key('backup_schedule_status_banner'), tone: _tone, message: _message!),
        ],
        if (s.history.isNotEmpty) ...[
          const SizedBox(height: MmsSpacing.sm),
          Text('Yedekleme geçmişi', style: TextStyle(fontSize: 12.5, color: colors.textSecondary)),
          for (final r in s.history.take(5))
            Text(
              '${_fmt(r.finishedAt)} · ${r.trigger == BackupTrigger.scheduled ? 'Otomatik' : 'Manuel'} · '
              '${r.success ? 'Başarılı${r.sizeBytes != null ? ' (${(r.sizeBytes! / 1024).toStringAsFixed(1)} KB)' : ''}' : 'Hata: ${r.errorCode}'}'
              '${r.postProcessError != null ? ' · Drive: bekliyor' : ''}',
              style: TextStyle(fontSize: 12, color: r.success ? colors.textSecondary : colors.dangerText),
            ),
        ],
      ],
    );
  }
}
