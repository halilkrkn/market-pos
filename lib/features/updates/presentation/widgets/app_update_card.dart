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

/// Tanı ekranında sürüm kontrolü ve güncelleme manifest kartı.
class AppUpdateCard extends ConsumerStatefulWidget {
  const AppUpdateCard({super.key});

  @override
  ConsumerState<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends ConsumerState<AppUpdateCard> {
  final _manifestController = TextEditingController();
  bool _isChecking = false;
  AppUpdateCheckResult? _lastResult;
  String? _syncedManifestUrl;

  @override
  void dispose() {
    _manifestController.dispose();
    super.dispose();
  }

  Future<void> _checkUpdates() async {
    setState(() => _isChecking = true);
    try {
      var target = _manifestController.text.trim();
      await ref.read(setupConfigProvider.notifier).updateManifestUrl(target);
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
    final setup = ref.watch(setupConfigProvider);
    final configured = setup.updateManifestUrl ?? '';
    if (_syncedManifestUrl != configured && _manifestController.text.isEmpty) {
      _manifestController.text = configured;
      _syncedManifestUrl = configured;
    }

    return DiagnosticsSectionCard(
      key: const Key('diagnostics_update_card'),
      title: 'Uygulama Sürümü ve Güncelleme Kontrolü',
      subtitle: 'Yerel ağ / Hub dağıtım manifesti üzerinden sürüm denetimi',
      trailing: const AppBadge(
        label: 'v${AppConstants.appVersion}',
        tone: AppBadgeTone.info,
        icon: Icons.system_update_alt_rounded,
        compact: true,
      ),
      children: [
        const DiagnosticsKeyValueRow(
          label: 'Yüklü İstemci Sürümü',
          value: AppConstants.appVersion,
          monospace: true,
        ),
        const SizedBox(height: MmsSpacing.sm),
        TextField(
          key: const Key('update_manifest_url_field'),
          controller: _manifestController,
          decoration: const InputDecoration(
            labelText: 'Güncelleme Manifest Adresi (Opsiyonel)',
            hintText: 'Örn: https://192.168.1.50:8945/api/v1/updates/manifest.json',
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
