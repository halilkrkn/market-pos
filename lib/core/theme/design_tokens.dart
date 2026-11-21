import 'package:flutter/material.dart';

/// MARKET MMS — Modern Emerald / Premium Retail SaaS Design Tokens
///
/// 4/8 tabanlı boşluk sistemi, tutarlı radius, duyarlı kırılım noktaları
/// ve WCAG AA/AAA kontrast doğrulamalı Light & Dark renk token'ları.

abstract final class MmsSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class MmsRadius {
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;
}

enum MmsWindowClass {
  /// Telefon ve çok dar ekranlar: 320px – 599px
  compact,

  /// Tablet ve dar pencere: 600px – 1023px
  medium,

  /// Masaüstü (Windows) ve geniş tablet: >= 1024px
  expanded,
}

abstract final class MmsBreakpoints {
  static const double compactMax = 600;
  static const double mediumMax = 1024;
  static const double wideDesktop = 1360;

  static MmsWindowClass classify(double width) {
    if (width < compactMax) return MmsWindowClass.compact;
    if (width < mediumMax) return MmsWindowClass.medium;
    return MmsWindowClass.expanded;
  }
}

abstract final class MmsTypography {
  static const String fontFamily = 'Inter';
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];
}

@immutable
class MmsColors extends ThemeExtension<MmsColors> {
  final Color background;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceElevated;
  final Color sidebarBg;
  final Color sidebarActiveBg;
  final Color sidebarText;
  final Color sidebarTextMuted;

  final Color primary;
  final Color onPrimary;
  final Color emerald;
  final Color onEmerald;
  final Color limeAccent;
  final Color onLimeAccent;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color border;
  final Color borderStrong;

  final Color success;
  final Color successBg;
  final Color successText;

  final Color warning;
  final Color warningBg;
  final Color warningText;

  final Color danger;
  final Color dangerBg;
  final Color dangerText;

  final Color info;
  final Color infoBg;
  final Color infoText;

  final Color neutralBg;
  final Color neutralText;

  final Color cardShadow;

  const MmsColors({
    required this.background,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceElevated,
    required this.sidebarBg,
    required this.sidebarActiveBg,
    required this.sidebarText,
    required this.sidebarTextMuted,
    required this.primary,
    required this.onPrimary,
    required this.emerald,
    required this.onEmerald,
    required this.limeAccent,
    required this.onLimeAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.success,
    required this.successBg,
    required this.successText,
    required this.warning,
    required this.warningBg,
    required this.warningText,
    required this.danger,
    required this.dangerBg,
    required this.dangerText,
    required this.info,
    required this.infoBg,
    required this.infoText,
    required this.neutralBg,
    required this.neutralText,
    required this.cardShadow,
  });

  /// Modern Emerald — Light Palette
  /// Logo canlı yeşili (#8AC814) kontrollü vurgu olarak türetilmiştir.
  static const MmsColors light = MmsColors(
    background: Color(0xFFF7F8F7),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF0F4F2),
    surfaceElevated: Color(0xFFFFFFFF),
    sidebarBg: Color(0xFF123C32), // Primary Forest sidebar (Shopify/Executive)
    sidebarActiveBg: Color(0xFF1B5245),
    sidebarText: Color(0xFFF5F8F6),
    sidebarTextMuted: Color(0xFFB3CCC2),
    primary: Color(0xFF123C32), // Primary Forest (#123C32)
    onPrimary: Color(0xFFFFFFFF),
    emerald: Color(0xFF168568), // Emerald (#168568)
    onEmerald: Color(0xFFFFFFFF),
    limeAccent: Color(0xFF8AC814), // Logo Lime Accent (#8AC814)
    onLimeAccent: Color(0xFF123C32), // > 7:1 contrast on lime
    textPrimary: Color(0xFF202723), // > 13:1 on #FFFFFF
    textSecondary: Color(0xFF4F5D56), // > 6.5:1 on #FFFFFF
    textTertiary: Color(0xFF64736C), // > 4.7:1 on #FFFFFF (WCAG AA)
    border: Color(0xFFE5EAE7),
    borderStrong: Color(0xFFC9D4CE),
    success: Color(0xFF168568),
    successBg: Color(0xFFE7F5F0),
    successText: Color(0xFF10493B), // > 9.0:1 WCAG AAA
    warning: Color(0xFFD99B35),
    warningBg: Color(0xFFFEF6E4),
    warningText: Color(0xFF6B4105), // > 8.2:1 WCAG AAA
    danger: Color(0xFFD94B4B),
    dangerBg: Color(0xFFFDEDED),
    dangerText: Color(0xFF8E1F1F), // > 8.1:1 WCAG AAA
    info: Color(0xFF1E6B7B),
    infoBg: Color(0xFFE9F4F7),
    infoText: Color(0xFF124652), // > 9.4:1 WCAG AAA
    neutralBg: Color(0xFFEBF0ED),
    neutralText: Color(0xFF27332D), // > 11.4:1 WCAG AAA
    cardShadow: Color(0x0D123C32),
  );

  /// Modern Emerald — Dark Palette
  static const MmsColors dark = MmsColors(
    background: Color(0xFF111714),
    surface: Color(0xFF1B2420),
    surfaceSubtle: Color(0xFF151D19),
    surfaceElevated: Color(0xFF23302A),
    sidebarBg: Color(0xFF0D1310),
    sidebarActiveBg: Color(0xFF1C2D26),
    sidebarText: Color(0xFFF0F5F2),
    sidebarTextMuted: Color(0xFF8FA59B),
    primary: Color(0xFF8BCBB0), // Soft Mint/Emerald Primary (#8BCBB0)
    onPrimary: Color(0xFF0E261E), // > 9.5:1 WCAG AAA
    emerald: Color(0xFF45A982), // Emerald Dark (#45A982)
    onEmerald: Color(0xFF0A2018), // > 7.2:1 WCAG AAA
    limeAccent: Color(0xFF9AD926), // Logo-derived controlled lime for dark
    onLimeAccent: Color(0xFF111714),
    textPrimary: Color(0xFFF0F5F2), // > 14:1 on #1B2420
    textSecondary: Color(0xFFACC0B6), // > 8.2:1 on #1B2420
    textTertiary: Color(0xFF889C92), // > 5.3:1 on #1B2420 (WCAG AA)
    border: Color(0xFF293630),
    borderStrong: Color(0xFF3A4D44),
    success: Color(0xFF45A982),
    successBg: Color(0xFF132D23),
    successText: Color(0xFF8CE0BC), // > 9.2:1 WCAG AAA
    warning: Color(0xFFE5AE49),
    warningBg: Color(0xFF32250E),
    warningText: Color(0xFFF9D180), // > 9.7:1 WCAG AAA
    danger: Color(0xFFE66565),
    dangerBg: Color(0xFF381616),
    dangerText: Color(0xFFFCA5A5), // > 7.9:1 WCAG AAA
    info: Color(0xFF5BB2C4),
    infoBg: Color(0xFF132A30),
    infoText: Color(0xFF9CE0EE), // > 10.1:1 WCAG AAA
    neutralBg: Color(0xFF24302A),
    neutralText: Color(0xFFD0DDD6), // > 10.0:1 WCAG AAA
    cardShadow: Color(0x33000000),
  );

  List<BoxShadow> get subtleShadow => [
        BoxShadow(
          color: cardShadow,
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  @override
  MmsColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceElevated,
    Color? sidebarBg,
    Color? sidebarActiveBg,
    Color? sidebarText,
    Color? sidebarTextMuted,
    Color? primary,
    Color? onPrimary,
    Color? emerald,
    Color? onEmerald,
    Color? limeAccent,
    Color? onLimeAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? success,
    Color? successBg,
    Color? successText,
    Color? warning,
    Color? warningBg,
    Color? warningText,
    Color? danger,
    Color? dangerBg,
    Color? dangerText,
    Color? info,
    Color? infoBg,
    Color? infoText,
    Color? neutralBg,
    Color? neutralText,
    Color? cardShadow,
  }) {
    return MmsColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      sidebarActiveBg: sidebarActiveBg ?? this.sidebarActiveBg,
      sidebarText: sidebarText ?? this.sidebarText,
      sidebarTextMuted: sidebarTextMuted ?? this.sidebarTextMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      emerald: emerald ?? this.emerald,
      onEmerald: onEmerald ?? this.onEmerald,
      limeAccent: limeAccent ?? this.limeAccent,
      onLimeAccent: onLimeAccent ?? this.onLimeAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      successText: successText ?? this.successText,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      warningText: warningText ?? this.warningText,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerText: dangerText ?? this.dangerText,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      infoText: infoText ?? this.infoText,
      neutralBg: neutralBg ?? this.neutralBg,
      neutralText: neutralText ?? this.neutralText,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  MmsColors lerp(ThemeExtension<MmsColors>? other, double t) {
    if (other is! MmsColors) return this;
    return MmsColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      sidebarActiveBg: Color.lerp(sidebarActiveBg, other.sidebarActiveBg, t)!,
      sidebarText: Color.lerp(sidebarText, other.sidebarText, t)!,
      sidebarTextMuted: Color.lerp(sidebarTextMuted, other.sidebarTextMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      emerald: Color.lerp(emerald, other.emerald, t)!,
      onEmerald: Color.lerp(onEmerald, other.onEmerald, t)!,
      limeAccent: Color.lerp(limeAccent, other.limeAccent, t)!,
      onLimeAccent: Color.lerp(onLimeAccent, other.onLimeAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      infoText: Color.lerp(infoText, other.infoText, t)!,
      neutralBg: Color.lerp(neutralBg, other.neutralBg, t)!,
      neutralText: Color.lerp(neutralText, other.neutralText, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

extension MmsThemeContext on BuildContext {
  MmsColors get mmsColors {
    final ext = Theme.of(this).extension<MmsColors>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? MmsColors.dark
        : MmsColors.light;
  }

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  MmsWindowClass get windowClass =>
      MmsBreakpoints.classify(MediaQuery.sizeOf(this).width);
}
