import 'package:flutter/material.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// MARKET MMS — Modern Emerald / Premium Retail SaaS Merkezi Tema Sistemi
///
/// Light, Dark ve System temalarını `MmsColors` Design Tokens üzerinden yönetir.
/// WCAG AA/AAA kontrast oranları, Fitts yasası (>=48dp dokunmatik hedefler)
/// ve `Inter` + Tabular Figures sayısal hizalamasını güvence altına alır.
class AppTheme {
  // Geriye dönük uyumlu Modern Emerald sabit takma adları
  static const Color primaryBlue = Color(0xFF123C32); // Primary Forest
  static const Color primaryEmerald = Color(0xFF168568); // Emerald
  static const Color limeAccent = Color(0xFF8AC814); // Logo Lime Accent
  static const Color primaryDark = Color(0xFF123C32);
  static const Color surfaceLight = Color(0xFFF7F8F7);
  static const Color cardBgLight = Color(0xFFFFFFFF);
  static const Color textMainLight = Color(0xFF202723);
  static const Color textMutedLight = Color(0xFF4F5D56);
  static const Color borderSubtle = Color(0xFFE5EAE7);

  // Durum Renkleri
  static const Color statusOnline = Color(0xFF168568);
  static const Color statusOffline = Color(0xFFD94B4B);
  static const Color statusWarning = Color(0xFFD99B35);

  // Rozet Semantik Renkleri (Light Tema - WCAG AAA)
  static const Color badgeSuccessBg = Color(0xFFE7F5F0);
  static const Color badgeSuccessText = Color(0xFF10493B);
  static const Color badgeErrorBg = Color(0xFFFDEDED);
  static const Color badgeErrorText = Color(0xFF8E1F1F);
  static const Color badgeWarningBg = Color(0xFFFEF6E4);
  static const Color badgeWarningText = Color(0xFF6B4105);
  static const Color badgeNeutralBg = Color(0xFFEBF0ED);
  static const Color badgeNeutralText = Color(0xFF27332D);

  // Rozet Semantik Renkleri (Dark Tema - WCAG AAA)
  static const Color badgeSuccessDarkBg = Color(0xFF132D23);
  static const Color badgeSuccessDarkText = Color(0xFF8CE0BC);
  static const Color badgeErrorDarkBg = Color(0xFF381616);
  static const Color badgeErrorDarkText = Color(0xFFFCA5A5);
  static const Color badgeWarningDarkBg = Color(0xFF32250E);
  static const Color badgeWarningDarkText = Color(0xFFF9D180);
  static const Color badgeNeutralDarkBg = Color(0xFF24302A);
  static const Color badgeNeutralDarkText = Color(0xFFD0DDD6);

  // POS Aksiyon & Semantik Renkler
  static const Color posCashAction = Color(0xFF168568);
  static const Color posCashBg = Color(0xFFE7F5F0);
  static const Color posCashText = Color(0xFF10493B);
  static const Color posWarningBg = Color(0xFFFEF6E4);
  static const Color posWarningText = Color(0xFF7A4E08);
  static const Color posDangerBg = Color(0xFFFDEDED);
  static const Color posDangerText = Color(0xFF8E1F1F);
  static const Color posInfoBg = Color(0xFFEAF4F0);

  static const List<FontFeature> tabularFiguresFeature =
      MmsTypography.tabularFigures;

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        colors: MmsColors.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        colors: MmsColors.dark,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required MmsColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.emerald,
      onSecondary: colors.onEmerald,
      tertiary: colors.limeAccent,
      onTertiary: colors.onLimeAccent,
      error: colors.danger,
      onError: Colors.white,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceSubtle,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.borderStrong,
    );

    final baseTextTheme = TextTheme(
      displaySmall: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      headlineLarge: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      headlineMedium: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      titleLarge: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: colors.textTertiary,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: MmsTypography.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: colors.textTertiary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: MmsTypography.fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.border,
      extensions: [colors],
      textTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MmsRadius.lg),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 8 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MmsRadius.xl),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MmsRadius.xl),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MmsSpacing.sm + 2,
          vertical: MmsSpacing.sm + 2,
        ),
        hintStyle: TextStyle(
          fontFamily: MmsTypography.fontFamily,
          color: colors.textTertiary,
          fontSize: 13.5,
        ),
        labelStyle: TextStyle(
          fontFamily: MmsTypography.fontFamily,
          color: colors.textSecondary,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          borderSide: BorderSide(color: colors.borderStrong, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          borderSide: BorderSide(color: colors.borderStrong, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          borderSide: BorderSide(color: colors.emerald, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          borderSide: BorderSide(color: colors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.neutralBg,
          disabledForegroundColor: colors.textTertiary,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: MmsTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.emerald,
          foregroundColor: colors.onEmerald,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: MmsTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: colors.borderStrong, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: MmsTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.emerald,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: MmsTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.emerald.withValues(alpha: isDark ? 0.22 : 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 76,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.emerald : colors.textSecondary,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: MmsTypography.fontFamily,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.primary : colors.textSecondary,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.emerald,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontFamily: MmsTypography.fontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: MmsTypography.fontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.primary,
        contentTextStyle: TextStyle(
          fontFamily: MmsTypography.fontFamily,
          color: colors.onPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MmsRadius.md),
        ),
      ),
      iconTheme: IconThemeData(
        size: 22,
        color: colors.textPrimary,
      ),
    );
  }
}
