import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../domain/app_update_info.dart';
import '../../update_providers.dart';

/// Ayarlar ve Sistem ekranında uygulama sürümü ve uzaktan güncelleme kartı.
class AppUpdateCard extends ConsumerWidget {
  const AppUpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final colors = context.mmsColors;

    final lastResult = updateState.lastResult;
    final errorMessage = updateState.errorMessage;
    final progress = updateState.downloadProgress;

    return DiagnosticsSectionCard(
      key: const Key('diagnostics_update_card'),
      title: 'Uygulama Sürümü ve Güncelleme',
      subtitle: 'Yüklü sürüm ve otomatik uzaktan güncelleme durumu',
      trailing: const AppBadge(
        label: 'v${AppConstants.appVersion}',
        tone: AppBadgeTone.info,
        icon: Icons.system_update_alt_rounded,
        compact: true,
      ),
      children: [
        const DiagnosticsKeyValueRow(
          label: 'Yüklü Sürüm',
          value: AppConstants.appVersion,
          monospace: true,
        ),
        const SizedBox(height: MmsSpacing.sm),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('check_updates_button'),
                onPressed: (updateState.isChecking || updateState.isDownloading)
                    ? null
                    : () => controller.checkForUpdates(),
                icon: const Icon(Icons.update_rounded),
                label: Text(
                  updateState.isChecking
                      ? 'Denetleniyor...'
                      : 'Güncellemeleri Denetle',
                ),
              ),
            ),
            if (updateState.hasAvailableUpdate)
              SizedBox(
                height: 48,
                child: FilledButton.tonalIcon(
                  key: const Key('install_update_button'),
                  onPressed:
                      (updateState.isChecking || updateState.isDownloading)
                      ? null
                      : () => controller.downloadAndInstall(),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    updateState.isDownloading
                        ? 'İndiriliyor...'
                        : 'İndir ve Güncelle',
                  ),
                ),
              ),
          ],
        ),
        if (updateState.isDownloading) ...[
          const SizedBox(height: MmsSpacing.sm),
          LinearProgressIndicator(
            key: const Key('update_download_progress'),
            value: progress,
          ),
          const SizedBox(height: MmsSpacing.xs),
          Text(
            progress != null
                ? 'İndiriliyor ve SHA-256 doğrulanıyor... %${(progress * 100).round()}'
                : 'İndiriliyor ve SHA-256 doğrulanıyor...',
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('update_status_banner'),
            tone: AppBadgeTone.danger,
            message: errorMessage,
          ),
        ] else if (lastResult != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('update_status_banner'),
            tone: switch (lastResult.availability) {
              AppUpdateAvailability.upToDate => AppBadgeTone.success,
              AppUpdateAvailability.updateAvailable => AppBadgeTone.info,
              AppUpdateAvailability.updateRequired => AppBadgeTone.warning,
              AppUpdateAvailability.unavailable => AppBadgeTone.neutral,
            },
            message: lastResult.message,
          ),
        ],
      ],
    );
  }
}
