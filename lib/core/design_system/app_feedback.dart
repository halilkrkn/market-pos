import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'app_buttons.dart';
import 'app_surfaces.dart';

/// Standartlaştırılmış MARKET MMS modal penceresi (Responsive genişlik + scrollable gövde).
class AppDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;
  final double? maxHeight;
  final VoidCallback? onClose;

  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.content,
    this.actions,
    this.maxWidth = 560,
    this.maxHeight,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final screenSize = MediaQuery.sizeOf(context);
    final effectiveMaxWidth =
        screenSize.width < 600 ? screenSize.width - 24 : maxWidth;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: MmsSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMaxWidth,
          maxHeight: maxHeight ?? screenSize.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MmsSpacing.lg,
                MmsSpacing.md,
                MmsSpacing.sm,
                MmsSpacing.md,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (iconColor ?? colors.emerald)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(MmsRadius.md),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: iconColor ?? colors.emerald,
                      ),
                    ),
                    const SizedBox(width: MmsSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Kapat',
                    size: screenSize.width < 600 ? 48 : 44,
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),

            // İçerik
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(MmsSpacing.lg),
                child: content,
              ),
            ),

            // Alt Aksiyon Çubuğu
            if (actions != null && actions!.isNotEmpty) ...[
              Divider(height: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MmsSpacing.lg,
                  vertical: MmsSpacing.sm,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: MmsSpacing.xs,
                  runSpacing: MmsSpacing.xs,
                  children: actions!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standartlaştırılmış mobil alt sayfa (Bottom Sheet) yardımcısı.
abstract final class AppBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder builder,
    List<Widget>? actions,
  }) {
    final colors = context.mmsColors;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: MmsSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(MmsRadius.pill),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MmsSpacing.lg,
                    MmsSpacing.sm,
                    MmsSpacing.xs,
                    MmsSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(MmsSpacing.lg),
                    child: builder(sheetContext),
                  ),
                ),
                if (actions != null && actions.isNotEmpty) ...[
                  Divider(height: 1, color: colors.border),
                  Padding(
                    padding: const EdgeInsets.all(MmsSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Standartlaştırılmış bildirim çubuğu yardımcısı.
abstract final class AppSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    AppBadgeTone tone = AppBadgeTone.info,
  }) {
    final colors = context.mmsColors;
    final (bg, fg, icon) = switch (tone) {
      AppBadgeTone.success => (
          colors.emerald,
          colors.onEmerald,
          Icons.check_circle_rounded
        ),
      AppBadgeTone.warning => (
          colors.warning,
          Colors.white,
          Icons.warning_amber_rounded
        ),
      AppBadgeTone.danger => (
          colors.danger,
          Colors.white,
          Icons.error_rounded
        ),
      _ => (colors.primary, colors.onPrimary, Icons.info_rounded),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: MmsSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// Standartlaştırılmış boş durum görünümü.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MmsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(MmsRadius.xl),
                border: Border.all(color: colors.border),
              ),
              child: Icon(icon, size: 28, color: colors.textTertiary),
            ),
            const SizedBox(height: MmsSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: MmsSpacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: MmsSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Standartlaştırılmış yükleme durumu.
class AppLoadingState extends StatelessWidget {
  final String? message;

  const AppLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MmsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.emerald,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: MmsSpacing.sm),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standartlaştırılmış hata durumu kartı.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool inline;

  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    if (inline) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MmsSpacing.md,
          vertical: MmsSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.dangerBg,
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 19, color: colors.dangerText),
            const SizedBox(width: MmsSpacing.xs),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.dangerText,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: MmsSpacing.xs),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: colors.dangerText),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ],
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MmsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.dangerBg,
                borderRadius: BorderRadius.circular(MmsRadius.xl),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 28,
                color: colors.dangerText,
              ),
            ),
            const SizedBox(height: MmsSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: MmsSpacing.md),
              AppButton(
                label: 'Tekrar Dene',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Çevrimdışı çalışma bilgilendirme göstergesi.
class AppOfflineIndicator extends StatelessWidget {
  final int pendingCount;
  final int failedCount;
  final int retryCount;
  final String? detailMessage;
  final VoidCallback? onRetrySync;

  const AppOfflineIndicator({
    super.key,
    required this.pendingCount,
    this.failedCount = 0,
    this.retryCount = 0,
    this.detailMessage,
    this.onRetrySync,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final String summaryText;
    if (failedCount > 0) {
      summaryText =
          'Çevrimdışı mod — $failedCount işlem senkronizasyon hatası veriyor, $pendingCount işlem bekliyor.';
    } else if (pendingCount > 0) {
      summaryText =
          'Çevrimdışı mod — $pendingCount işlem yerel kuyrukta güvenle bekliyor.';
    } else if (retryCount > 0) {
      summaryText =
          'Çevrimdışı mod — $retryCount işlem bağlantı geldiğinde yeniden denenecek.';
    } else {
      summaryText =
          'Çevrimdışı mod — İşlemler yerel veritabanında kesintisiz kaydedilir.';
    }

    return Container(
      key: const Key('app_offline_indicator'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: MmsSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.warningBg,
        border: Border(
          bottom: BorderSide(color: colors.warning.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 17, color: colors.warningText),
          const SizedBox(width: MmsSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summaryText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.warningText,
                  ),
                ),
                if (detailMessage != null && detailMessage!.trim().isNotEmpty)
                  Text(
                    detailMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.warningText.withValues(alpha: 0.9),
                    ),
                  ),
              ],
            ),
          ),
          if (onRetrySync != null)
            TextButton(
              onPressed: onRetrySync,
              style: TextButton.styleFrom(
                foregroundColor: colors.warningText,
                minimumSize: const Size(64, 48),
              ),
              child: const Text(
                'Tekrar Dene',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
