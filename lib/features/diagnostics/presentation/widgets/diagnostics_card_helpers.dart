import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';

/// Tanı ekranındaki Faz 7 kartları için ortak yüzey, satır ve durum bildirimi yardımcıları.
class DiagnosticsSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  const DiagnosticsSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          Divider(height: MmsSpacing.lg, color: colors.border),
          ...children,
        ],
      ),
    );
  }
}

class DiagnosticsKeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const DiagnosticsKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: MmsSpacing.sm),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: monospace ? MmsTypography.tabularFigures : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiagnosticsInlineBanner extends StatelessWidget {
  final AppBadgeTone tone;
  final String message;

  const DiagnosticsInlineBanner({
    super.key,
    required this.tone,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final (Color bg, Color fg, Color border, IconData icon) = switch (tone) {
      AppBadgeTone.success => (
          colors.successBg,
          colors.successText,
          colors.success.withValues(alpha: 0.4),
          Icons.check_circle_outline_rounded,
        ),
      AppBadgeTone.warning => (
          colors.warningBg,
          colors.warningText,
          colors.warning.withValues(alpha: 0.4),
          Icons.warning_amber_rounded,
        ),
      AppBadgeTone.danger => (
          colors.dangerBg,
          colors.dangerText,
          colors.danger.withValues(alpha: 0.45),
          Icons.error_outline_rounded,
        ),
      AppBadgeTone.info => (
          colors.infoBg,
          colors.infoText,
          colors.info.withValues(alpha: 0.4),
          Icons.info_outline_rounded,
        ),
      AppBadgeTone.neutral || AppBadgeTone.lime => (
          colors.neutralBg,
          colors.neutralText,
          colors.border,
          Icons.info_outline_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: MmsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MmsRadius.sm),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: MmsSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
