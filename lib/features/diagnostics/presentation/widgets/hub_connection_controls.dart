import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../../sync/domain/hub_connection_state.dart';
import '../../application/system_status_notifier.dart';

/// Diagnostics ekranı için Master Hub yeniden keşif, bağlantı yenileme ve
/// manuel IP/URL giriş bileşeni (Faz 1.3).
class HubConnectionControls extends ConsumerStatefulWidget {
  const HubConnectionControls({super.key});

  @override
  ConsumerState<HubConnectionControls> createState() =>
      _HubConnectionControlsState();
}

class _HubConnectionControlsState extends ConsumerState<HubConnectionControls> {
  final TextEditingController _urlController = TextEditingController();
  String? _feedbackMessage;
  bool _isFeedbackSuccess = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleRediscover() async {
    setState(() {
      _feedbackMessage = null;
    });
    final found =
        await ref.read(hubConnectionProvider.notifier).discoverAndConnect();
    if (!mounted) return;
    if (found) {
      await ref.read(systemStatusProvider.notifier).refreshStatus();
      if (!mounted) return;
    }
    final latest = ref.read(hubConnectionProvider);
    setState(() {
      _isFeedbackSuccess = found;
      _feedbackMessage = found
          ? 'Hub otomatik keşif ile doğrulandı: ${latest.activeHubUrl ?? ''}'
          : (latest.errorMessage ?? 'Yerel ağda Hub bulunamadı.');
    });
  }

  Future<void> _handleReconnect() async {
    setState(() {
      _feedbackMessage = null;
    });
    final ok = await ref
        .read(hubConnectionProvider.notifier)
        .ensureConnectedOrDiscover(force: true);
    if (!mounted) return;
    if (ok) {
      await ref.read(systemStatusProvider.notifier).refreshStatus();
      if (!mounted) return;
    }
    final latest = ref.read(hubConnectionProvider);
    setState(() {
      _isFeedbackSuccess = ok;
      _feedbackMessage = ok
          ? 'Hub bağlantısı doğrulandı: ${latest.activeHubUrl ?? ''}'
          : (latest.errorMessage ?? 'Hub şu anda erişilebilir değil.');
    });
  }

  Future<void> _handleManualConnect() async {
    setState(() {
      _feedbackMessage = null;
    });
    final result = await ref
        .read(hubConnectionProvider.notifier)
        .connectToManualAddress(_urlController.text);
    if (!mounted) return;
    if (result.isSuccess) {
      await ref.read(systemStatusProvider.notifier).refreshStatus();
      if (!mounted) return;
    }
    setState(() {
      _isFeedbackSuccess = result.isSuccess;
      _feedbackMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hubState = ref.watch(hubConnectionProvider);
    final colors = context.mmsColors;
    final bool isBusy =
        hubState.isBusy || hubState.phase == HubConnectionPhase.discovering;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MmsSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(MmsRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MmsSpacing.xs,
            runSpacing: MmsSpacing.xs,
            children: [
              AppButton(
                key: const Key('diagnostics_discover_hub_button'),
                label: 'Hub\'ı Yeniden Ara',
                icon: Icons.wifi_tethering_rounded,
                variant: AppButtonVariant.emerald,
                isLoading: hubState.phase == HubConnectionPhase.discovering,
                minHeight: 48,
                onPressed: isBusy ? null : _handleRediscover,
              ),
              AppButton(
                key: const Key('diagnostics_reconnect_hub_button'),
                label: 'Bağlantıyı Yenile',
                icon: Icons.sync_rounded,
                variant: AppButtonVariant.secondary,
                minHeight: 48,
                onPressed: isBusy ? null : _handleReconnect,
              ),
            ],
          ),
          const SizedBox(height: MmsSpacing.md),
          Text(
            'Manuel Hub Adresi veya IP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: MmsSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool stackVertical = constraints.maxWidth < 480;
              final inputField = TextField(
                key: const Key('diagnostics_manual_hub_input'),
                controller: _urlController,
                enabled: !isBusy,
                keyboardType: TextInputType.url,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colors.textPrimary,
                  fontFeatures: MmsTypography.tabularFigures,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Örn: 192.168.1.158 veya https://192.168.1.158:8945',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: MmsSpacing.md,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                    borderSide: BorderSide(color: colors.borderStrong),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                    borderSide: BorderSide(color: colors.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                ),
                onChanged: (_) {
                  if (_feedbackMessage != null) {
                    setState(() => _feedbackMessage = null);
                  }
                },
                onSubmitted: (_) {
                  if (!isBusy) _handleManualConnect();
                },
              );

              final saveButton = AppButton(
                key: const Key('diagnostics_save_manual_hub_button'),
                label: 'Kaydet ve Bağlan',
                icon: Icons.check_circle_outline_rounded,
                variant: AppButtonVariant.primary,
                minHeight: 48,
                expand: stackVertical,
                onPressed: isBusy ? null : _handleManualConnect,
              );

              if (stackVertical) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    inputField,
                    const SizedBox(height: MmsSpacing.xs),
                    saveButton,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: inputField),
                  const SizedBox(width: MmsSpacing.xs),
                  saveButton,
                ],
              );
            },
          ),
          if (_feedbackMessage != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            Container(
              key: const Key('diagnostics_hub_action_feedback'),
              width: double.infinity,
              padding: const EdgeInsets.all(MmsSpacing.sm),
              decoration: BoxDecoration(
                color: _isFeedbackSuccess ? colors.successBg : colors.dangerBg,
                borderRadius: BorderRadius.circular(MmsRadius.sm),
                border: Border.all(
                  color: _isFeedbackSuccess
                      ? colors.successText
                      : colors.dangerText,
                ),
              ),
              child: Text(
                _feedbackMessage!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      _isFeedbackSuccess ? colors.successText : colors.dangerText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
