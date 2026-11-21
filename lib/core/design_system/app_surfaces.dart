import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Standartlaştırılmış MARKET MMS yüzey kartı.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool elevated;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MmsSpacing.lg),
    this.backgroundColor,
    this.borderColor,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final box = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(MmsRadius.lg),
        border: Border.all(
          color: borderColor ?? colors.border,
          width: 1,
        ),
        boxShadow: elevated ? colors.subtleShadow : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return box;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(MmsRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MmsRadius.lg),
        child: box,
      ),
    );
  }
}

enum AppBadgeTone {
  success,
  warning,
  danger,
  info,
  neutral,
  lime,
}

/// Standartlaştırılmış semantik durum rozeti (WCAG AAA Light/Dark uyumlu).
class AppBadge extends StatelessWidget {
  final String label;
  final AppBadgeTone tone;
  final IconData? icon;
  final bool compact;

  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final (bg, fg) = _resolveColors(colors);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? MmsSpacing.xs : MmsSpacing.sm,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MmsRadius.pill),
        border: Border.all(color: fg.withValues(alpha: 0.24), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 13 : 15, color: fg),
            SizedBox(width: compact ? 4 : 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: MmsTypography.fontFamily,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.25,
                color: fg,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _resolveColors(MmsColors colors) {
    switch (tone) {
      case AppBadgeTone.success:
        return (colors.successBg, colors.successText);
      case AppBadgeTone.warning:
        return (colors.warningBg, colors.warningText);
      case AppBadgeTone.danger:
        return (colors.dangerBg, colors.dangerText);
      case AppBadgeTone.info:
        return (colors.infoBg, colors.infoText);
      case AppBadgeTone.neutral:
        return (colors.neutralBg, colors.neutralText);
      case AppBadgeTone.lime:
        return (colors.limeAccent.withValues(alpha: 0.22), colors.primary);
    }
  }
}

/// Standartlaştırılmış KPI / İstatistik kartı (Tabular Figures + Responsive).
class AppStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;
  final String? subtitle;
  final VoidCallback? onTap;

  const AppStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.tone = AppBadgeTone.success,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final (accentBg, accentFg) = switch (tone) {
      AppBadgeTone.success => (colors.successBg, colors.successText),
      AppBadgeTone.warning => (colors.warningBg, colors.warningText),
      AppBadgeTone.danger => (colors.dangerBg, colors.dangerText),
      AppBadgeTone.info => (colors.infoBg, colors.infoText),
      AppBadgeTone.neutral => (colors.neutralBg, colors.neutralText),
      AppBadgeTone.lime => (
          colors.limeAccent.withValues(alpha: 0.2),
          colors.primary
        ),
    };

    return AppCard(
      onTap: onTap,
      elevated: true,
      padding: const EdgeInsets.all(MmsSpacing.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(MmsRadius.md),
            ),
            child: Icon(icon, size: 21, color: accentFg),
          ),
          const SizedBox(width: MmsSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                      fontFeatures: MmsTypography.tabularFigures,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standartlaştırılmış veri tablosu kapsayıcısı (Shopify Admin / Odoo veri yoğunluğu).
class AppDataTable extends StatelessWidget {
  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? emptyState;
  final Widget? footer;

  const AppDataTable({
    super.key,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    this.emptyState,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(MmsRadius.lg),
        border: Border.all(color: colors.border),
        boxShadow: colors.subtleShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MmsSpacing.md,
              vertical: MmsSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: header,
          ),
          Expanded(
            child: itemCount == 0
                ? (emptyState ?? const SizedBox.shrink())
                : ListView.separated(
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: colors.border,
                    ),
                    itemBuilder: itemBuilder,
                  ),
          ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MmsSpacing.md,
                vertical: MmsSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}
