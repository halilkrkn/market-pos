import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../../setup/setup_providers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../data/app_update_checker.dart';
import '../../domain/app_update_info.dart';

/// Gelişmiş bölümde uygulama sürümü ve güncelleme durumu kartı.
class AppUpdateCard extends ConsumerStatefulWidget {
  const AppUpdateCard({super.key});

  @override
  ConsumerState<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends ConsumerState<AppUpdateCard> {
  bool _isChecking = false;
  AppUpdateCheckResult? _lastResult;

  Future<void> _checkUpdates() async {
    setState(() => _isChecking = true);
    try {
      var target = (ref.read(setupConfigProvider).updateManifestUrl ?? '').trim();
      if (target.isEmpty) {
        final hubUrl = ref.read(hubConnectionProvider).activeHubUrl;
        if (hubUrl != null && hubUrl.isNotEmpty) {
          target =
              '${hubUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/updates/manifest.json';
        }
      }
      const checker = AppUpdateChecker();
      final result = await checker.checkManifestUrl(target);
      if (!mounted) return;
      setState(() => _lastResult = result);
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiagnosticsSectionCard(
      key: const Key('diagnostics_update_card'),
      title: 'Uygulama Sürümü ve Güncelleme',
      subtitle: 'Yüklü sürüm ve güncelleme durumu',
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
                onPressed: _isChecking ? null : _checkUpdates,
                icon: const Icon(Icons.update_rounded),
                label: Text(
                  _isChecking ? 'Denetleniyor...' : 'Güncellemeyi Denetle',
                ),
              ),
            ),
          ],
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('update_status_banner'),
            tone: switch (_lastResult!.availability) {
              AppUpdateAvailability.upToDate => AppBadgeTone.success,
              AppUpdateAvailability.updateAvailable => AppBadgeTone.info,
              AppUpdateAvailability.updateRequired => AppBadgeTone.warning,
              AppUpdateAvailability.unavailable => AppBadgeTone.neutral,
            },
            message: _lastResult!.message,
          ),
        ],
      ],
    );
  }
}
