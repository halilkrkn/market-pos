import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

enum AppButtonVariant {
  primary,
  emerald,
  secondary,
  ghost,
  danger,
}

/// Standartlaştırılmış MARKET MMS aksiyon butonu (Minimum 48dp dokunmatik hedef).
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool expand;
  final double minHeight;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.expand = false,
    this.minHeight = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    final Widget content = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foregroundColor(colors),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: MmsSpacing.xs),
              ],
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.emerald:
      case AppButtonVariant.danger:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _backgroundColor(colors),
            foregroundColor: _foregroundColor(colors),
            disabledBackgroundColor: colors.neutralBg,
            disabledForegroundColor: colors.textTertiary,
            elevation: 0,
            minimumSize: Size(expand ? double.infinity : 64, minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MmsRadius.sm),
            ),
          ),
          child: content,
        );
        break;
      case AppButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            backgroundColor: colors.surface,
            side: BorderSide(color: colors.borderStrong, width: 1.2),
            minimumSize: Size(expand ? double.infinity : 64, minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MmsRadius.sm),
            ),
          ),
          child: content,
        );
        break;
      case AppButtonVariant.ghost:
        button = TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.emerald,
            minimumSize: Size(expand ? double.infinity : 48, minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MmsRadius.sm),
            ),
          ),
          child: content,
        );
        break;
    }

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  Color _backgroundColor(MmsColors colors) {
    switch (variant) {
      case AppButtonVariant.primary:
        return colors.primary;
      case AppButtonVariant.emerald:
        return colors.emerald;
      case AppButtonVariant.danger:
        return colors.danger;
      case AppButtonVariant.secondary:
      case AppButtonVariant.ghost:
        return Colors.transparent;
    }
  }

  Color _foregroundColor(MmsColors colors) {
    switch (variant) {
      case AppButtonVariant.primary:
        return colors.onPrimary;
      case AppButtonVariant.emerald:
        return colors.onEmerald;
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.secondary:
        return colors.textPrimary;
      case AppButtonVariant.ghost:
        return colors.emerald;
    }
  }
}

/// Standartlaştırılmış MARKET MMS ikon butonu (>=44dp hedef).
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final bool bordered;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.bordered = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        fixedSize: Size(size, size),
        foregroundColor: color ?? colors.textSecondary,
        backgroundColor: backgroundColor ??
            (bordered ? colors.surface : Colors.transparent),
        side: bordered ? BorderSide(color: colors.borderStrong) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
        ),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
