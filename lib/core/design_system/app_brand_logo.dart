import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// MARKET MMS — Merkezi Marka Logosu Widget'ı
///
/// Kullanıcı tarafından sağlanan orijinal alışveriş çantası/sepet sembolünü
/// yeniden çizmeden, en-boy oranını (1:1) koruyarak Light ve Dark temalarda
/// şeffaf arka planlı olarak sunar.
class AppBrandLogo extends StatelessWidget {
  static const String assetPath = 'assets/branding/mms_logo.png';

  final double size;
  final bool showWordmark;
  final bool useLightText;
  final String? subtitle;
  final bool compact;

  const AppBrandLogo.mark({
    super.key,
    this.size = 32,
  })  : showWordmark = false,
        useLightText = false,
        subtitle = null,
        compact = false;

  const AppBrandLogo.lockup({
    super.key,
    this.size = 36,
    this.useLightText = false,
    this.subtitle,
    this.compact = false,
  }) : showWordmark = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    final symbol = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'MARKET MMS Logo',
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.shopping_bag_rounded,
          size: size * 0.85,
          color: colors.emerald,
        ),
      ),
    );

    if (!showWordmark) {
      return symbol;
    }

    final titleColor = useLightText ? colors.sidebarText : colors.textPrimary;
    final subColor =
        useLightText ? colors.sidebarTextMuted : colors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        SizedBox(width: compact ? MmsSpacing.xs : MmsSpacing.sm),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact ? 'MARKET MMS' : 'MARKET MANAGEMENT SYSTEM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: MmsTypography.fontFamily,
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: titleColor,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: MmsTypography.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
